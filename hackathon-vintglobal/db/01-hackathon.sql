--
-- PostgreSQL database dump
--

\restrict a1EvXQZZhgkzsd27MbOpm1DIYAwnmThqfm1bhvWgpQKTuRRC1T9iqjtyMeff3Zw

-- Dumped from database version 17.9 (Debian 17.9-1.pgdg13+1)
-- Dumped by pg_dump version 18.4

-- Started on 2026-10-27 17:33:33

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- TOC entry 8 (class 2615 OID 95621)
-- Name: InHire; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA "InHire";


ALTER SCHEMA "InHire" OWNER TO postgres;

--
-- TOC entry 257 (class 1255 OID 95931)
-- Name: buscar_profissionais(integer, integer, bigint, bigint[], integer, bigint[], bigint); Type: FUNCTION; Schema: InHire; Owner: postgres
--

CREATE FUNCTION "InHire".buscar_profissionais(p_ano integer, p_mes integer, p_senioridade bigint DEFAULT NULL::bigint, p_skills bigint[] DEFAULT '{}'::bigint[], p_disponibilidade_min integer DEFAULT 0, p_cargos bigint[] DEFAULT NULL::bigint[], p_colaborador bigint DEFAULT NULL::bigint) RETURNS TABLE(id_colaborador bigint, nome_ficticio character varying, id_cargo bigint, id_senioridade bigint, total_alocado bigint, disponibilidade bigint)
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog', 'InHire'
    AS $$
BEGIN
 IF p_ano IS NULL OR p_ano NOT BETWEEN 1 AND 9999 OR p_mes IS NULL OR p_mes NOT BETWEEN 1 AND 12
 OR p_disponibilidade_min IS NULL OR p_disponibilidade_min>100
 OR (p_senioridade IS NOT NULL AND p_senioridade<=0)
 OR (p_colaborador IS NOT NULL AND p_colaborador<=0)
 OR EXISTS(SELECT 1 FROM unnest(p_skills) id WHERE id IS NULL OR id<=0)
 OR EXISTS(SELECT 1 FROM unnest(p_cargos) id WHERE id IS NULL OR id<=0)
 THEN RAISE EXCEPTION 'Parametros de busca invalidos' USING ERRCODE='22023'; END IF;
 RETURN QUERY
 SELECT c.id,c.nome_abreviado,c.id_cargo,c.id_senioridade,d.total_alocado,d.disponibilidade
 FROM "InHire".disponibilidade_mensal(p_ano,p_mes) d
 JOIN "InHire".colaboradores c ON c.id=d.id_colaborador
 WHERE c.status IS TRUE AND c.deletado IS FALSE
 AND (p_senioridade IS NULL OR c.id_senioridade=p_senioridade)
 AND (p_cargos IS NULL OR c.id_cargo=ANY(p_cargos))
 AND (p_colaborador IS NULL OR c.id=p_colaborador)
 AND d.disponibilidade>=p_disponibilidade_min
 AND NOT EXISTS(
  SELECT 1 FROM unnest(coalesce(p_skills,'{}'::BIGINT[])) requerida(id)
  WHERE NOT EXISTS(SELECT 1 FROM "InHire".colaborador_skills cs
    JOIN "InHire".skills s ON s.id=cs.id_skill
    WHERE cs.id_colaborador=c.id AND s.id=requerida.id
      AND cs.status IS TRUE AND cs.deletado IS FALSE
      AND s.status IS TRUE AND s.deletado IS FALSE)
 );
END;
$$;


ALTER FUNCTION "InHire".buscar_profissionais(p_ano integer, p_mes integer, p_senioridade bigint, p_skills bigint[], p_disponibilidade_min integer, p_cargos bigint[], p_colaborador bigint) OWNER TO postgres;

--
-- TOC entry 256 (class 1255 OID 95930)
-- Name: disponibilidade_mensal(integer, integer); Type: FUNCTION; Schema: InHire; Owner: postgres
--

CREATE FUNCTION "InHire".disponibilidade_mensal(p_ano integer, p_mes integer) RETURNS TABLE(id_colaborador bigint, ano integer, mes integer, total_alocado bigint, disponibilidade bigint, status_colaborador boolean, colaborador_excluido boolean)
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog', 'InHire'
    AS $$
DECLARE v_mes TEXT;
BEGIN
    IF p_ano IS NULL OR p_ano NOT BETWEEN 1 AND 9999
       OR p_mes IS NULL OR p_mes NOT BETWEEN 1 AND 12 THEN
        RAISE EXCEPTION 'Ano ou mes invalido' USING ERRCODE = '22023';
    END IF;
    v_mes := (ARRAY['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'])[p_mes];
    RETURN QUERY
    WITH totais AS (
        SELECT a.id_colaborador, sum(p.porcentagem) percentual
        FROM "InHire".planejamentos p
        JOIN "InHire".alocacoes a ON a.id=p.id_alocacao
        WHERE p.ano=p_ano AND p.mes=v_mes
          AND p.status IS TRUE AND p.deletado IS FALSE
          AND a.status IS TRUE AND a.deletado IS FALSE
        GROUP BY a.id_colaborador
    )
    SELECT c.id,p_ano,p_mes,coalesce(t.percentual,0::BIGINT),
           100::BIGINT-coalesce(t.percentual,0::BIGINT),c.status,c.deletado
    FROM "InHire".colaboradores c LEFT JOIN totais t ON t.id_colaborador=c.id;
END;
$$;


ALTER FUNCTION "InHire".disponibilidade_mensal(p_ano integer, p_mes integer) OWNER TO postgres;

--
-- TOC entry 259 (class 1255 OID 96262)
-- Name: disponibilidade_periodo(integer, integer, integer, integer); Type: FUNCTION; Schema: InHire; Owner: postgres
--

CREATE FUNCTION "InHire".disponibilidade_periodo(p_ano_inicio integer, p_mes_inicio integer, p_ano_fim integer, p_mes_fim integer) RETURNS TABLE(id_colaborador bigint, meses integer, disponibilidade_media numeric, disponibilidade_minima bigint, disponibilidade_maxima bigint, meses_sem_alocacao integer)
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog', 'InHire'
    AS $$
BEGIN
 IF p_ano_inicio IS NULL OR p_ano_fim IS NULL
 OR p_ano_inicio NOT BETWEEN 1 AND 9999 OR p_ano_fim NOT BETWEEN 1 AND 9999
 OR p_mes_inicio IS NULL OR p_mes_fim IS NULL
 OR p_mes_inicio NOT BETWEEN 1 AND 12 OR p_mes_fim NOT BETWEEN 1 AND 12
 OR (p_ano_fim*12+p_mes_fim)<(p_ano_inicio*12+p_mes_inicio)
 OR (p_ano_fim*12+p_mes_fim)-(p_ano_inicio*12+p_mes_inicio)>60
 THEN RAISE EXCEPTION 'Periodo invalido ou superior a 61 meses' USING ERRCODE='22023'; END IF;
 RETURN QUERY
 WITH calendario AS (
  SELECT n, (n-1)/12 AS ano, (n-1)%12+1 AS mes
  FROM generate_series(p_ano_inicio*12+p_mes_inicio,p_ano_fim*12+p_mes_fim) n
 ), quadro AS (
  SELECT f.id_colaborador, f.disponibilidade, f.total_alocado
  FROM calendario k
  CROSS JOIN LATERAL "InHire".disponibilidade_mensal(k.ano,k.mes) f
 )
 SELECT q.id_colaborador, count(*)::integer, round(avg(q.disponibilidade),2),
        min(q.disponibilidade), max(q.disponibilidade),
        count(*) FILTER (WHERE q.total_alocado=0)::integer
 FROM quadro q GROUP BY q.id_colaborador ORDER BY q.id_colaborador;
END
$$;


ALTER FUNCTION "InHire".disponibilidade_periodo(p_ano_inicio integer, p_mes_inicio integer, p_ano_fim integer, p_mes_fim integer) OWNER TO postgres;

--
-- TOC entry 258 (class 1255 OID 96261)
-- Name: ranking_skills(integer, integer, text[], integer, boolean, bigint); Type: FUNCTION; Schema: InHire; Owner: postgres
--

CREATE FUNCTION "InHire".ranking_skills(p_ano integer, p_mes integer, p_skills text[], p_disponibilidade_min integer DEFAULT 0, p_match_completo boolean DEFAULT false, p_senioridade bigint DEFAULT NULL::bigint) RETURNS TABLE(id_colaborador bigint, nome_ficticio character varying, senioridade text, skills_atendidas bigint, skills_pedidas bigint, score_percentual numeric, total_alocado bigint, disponibilidade bigint)
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog', 'InHire'
    AS $$
BEGIN
 IF p_ano IS NULL OR p_ano NOT BETWEEN 1 AND 9999 OR p_mes IS NULL OR p_mes NOT BETWEEN 1 AND 12
 OR p_skills IS NULL OR cardinality(p_skills)=0 OR p_disponibilidade_min IS NULL
 OR p_disponibilidade_min NOT BETWEEN -1000 AND 100
 OR EXISTS (SELECT 1 FROM unnest(p_skills) s WHERE s IS NULL OR btrim(s)='')
 THEN RAISE EXCEPTION 'Parametros invalidos' USING ERRCODE='22023'; END IF;
 RETURN QUERY
 WITH requeridas AS (
   SELECT DISTINCT lower(btrim(s)) nome FROM unnest(p_skills) s
 ), matches AS (
   SELECT c.id, count(DISTINCT r.nome) atendidas
   FROM "InHire".colaboradores c
   JOIN "InHire".colaborador_skills cs ON cs.id_colaborador=c.id AND cs.status AND NOT cs.deletado
   JOIN "InHire".skills sk ON sk.id=cs.id_skill AND sk.status AND NOT sk.deletado
   JOIN requeridas r ON lower(btrim(sk.nome_skill))=r.nome
   GROUP BY c.id
 )
 SELECT c.id, c.nome_abreviado, ds.descricao::text,
        coalesce(m.atendidas,0)::bigint, (SELECT count(*) FROM requeridas)::bigint,
        round(coalesce(m.atendidas,0)::numeric * 100 / (SELECT count(*) FROM requeridas),2),
        disp.total_alocado,disp.disponibilidade
 FROM "InHire".colaboradores c
 JOIN "InHire".disponibilidade_mensal(p_ano,p_mes) disp ON disp.id_colaborador=c.id
 LEFT JOIN "InHire".dominios ds ON ds.id=c.id_senioridade
 LEFT JOIN matches m ON m.id=c.id
 WHERE c.status AND NOT c.deletado
   AND (p_senioridade IS NULL OR c.id_senioridade=p_senioridade)
   AND disp.disponibilidade>=p_disponibilidade_min
   AND coalesce(m.atendidas,0)>0
   AND (NOT p_match_completo OR m.atendidas=(SELECT count(*) FROM requeridas))
 ORDER BY 6 DESC, 8 DESC, 1;
END
$$;


ALTER FUNCTION "InHire".ranking_skills(p_ano integer, p_mes integer, p_skills text[], p_disponibilidade_min integer, p_match_completo boolean, p_senioridade bigint) OWNER TO postgres;

--
-- TOC entry 260 (class 1255 OID 96263)
-- Name: ranking_talentos(text[], boolean); Type: FUNCTION; Schema: InHire; Owner: postgres
--

CREATE FUNCTION "InHire".ranking_talentos(p_skills text[], p_match_completo boolean DEFAULT false) RETURNS TABLE(id_talento bigint, nome_talento character varying, skills_atendidas bigint, skills_pedidas bigint, score_percentual numeric)
    LANGUAGE plpgsql STABLE
    SET search_path TO 'pg_catalog', 'InHire'
    AS $$
BEGIN
 IF p_skills IS NULL OR cardinality(p_skills)=0 OR EXISTS (
  SELECT 1 FROM unnest(p_skills) s WHERE s IS NULL OR btrim(s)=''
 ) THEN RAISE EXCEPTION 'Skills invalidas' USING ERRCODE='22023'; END IF;
 RETURN QUERY
 WITH r AS (SELECT DISTINCT lower(btrim(s)) nome FROM unnest(p_skills) s),
 m AS (
  SELECT t.id,count(DISTINCT r.nome) qtd
  FROM "InHire".talentos t
  JOIN "InHire".talento_skills ts ON ts.id_talento=t.id
  JOIN "InHire".skills sk ON sk.id=ts.id_skill AND sk.status AND NOT sk.deletado
  JOIN r ON r.nome=lower(btrim(sk.nome_skill))
  WHERE t.status GROUP BY t.id
 )
 SELECT t.id,t.nome_abreviado,m.qtd,(SELECT count(*) FROM r),
        round(m.qtd::numeric*100/(SELECT count(*) FROM r),2)
 FROM "InHire".talentos t JOIN m ON m.id=t.id
 WHERE NOT p_match_completo OR m.qtd=(SELECT count(*) FROM r)
 ORDER BY 5 DESC,1;
END
$$;


ALTER FUNCTION "InHire".ranking_talentos(p_skills text[], p_match_completo boolean) OWNER TO postgres;

--
-- TOC entry 237 (class 1259 OID 95808)
-- Name: alocacoes; Type: TABLE; Schema: InHire; Owner: postgres
--

CREATE TABLE "InHire".alocacoes (
    id bigint NOT NULL,
    id_colaborador bigint NOT NULL,
    id_demanda bigint NOT NULL,
    status boolean DEFAULT true NOT NULL,
    deletado boolean DEFAULT false NOT NULL
);


ALTER TABLE "InHire".alocacoes OWNER TO postgres;

--
-- TOC entry 236 (class 1259 OID 95807)
-- Name: alocacoes_id_seq; Type: SEQUENCE; Schema: InHire; Owner: postgres
--

CREATE SEQUENCE "InHire".alocacoes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "InHire".alocacoes_id_seq OWNER TO postgres;

--
-- TOC entry 3647 (class 0 OID 0)
-- Dependencies: 236
-- Name: alocacoes_id_seq; Type: SEQUENCE OWNED BY; Schema: InHire; Owner: postgres
--

ALTER SEQUENCE "InHire".alocacoes_id_seq OWNED BY "InHire".alocacoes.id;


--
-- TOC entry 233 (class 1259 OID 95764)
-- Name: colaborador_skills; Type: TABLE; Schema: InHire; Owner: postgres
--

CREATE TABLE "InHire".colaborador_skills (
    id bigint NOT NULL,
    id_colaborador bigint NOT NULL,
    id_skill bigint NOT NULL,
    nivel_conhecimento character varying(20) NOT NULL,
    id_nivel_conhecimento bigint NOT NULL,
    status boolean DEFAULT true NOT NULL,
    deletado boolean DEFAULT false NOT NULL,
    CONSTRAINT colaborador_skills_nivel_conhecimento_check CHECK (((nivel_conhecimento)::text = ANY ((ARRAY['BASICO'::character varying, 'INTERMEDIARIO'::character varying, 'AVANCADO'::character varying])::text[])))
);


ALTER TABLE "InHire".colaborador_skills OWNER TO postgres;

--
-- TOC entry 232 (class 1259 OID 95763)
-- Name: colaborador_skills_id_seq; Type: SEQUENCE; Schema: InHire; Owner: postgres
--

CREATE SEQUENCE "InHire".colaborador_skills_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "InHire".colaborador_skills_id_seq OWNER TO postgres;

--
-- TOC entry 3648 (class 0 OID 0)
-- Dependencies: 232
-- Name: colaborador_skills_id_seq; Type: SEQUENCE OWNED BY; Schema: InHire; Owner: postgres
--

ALTER SEQUENCE "InHire".colaborador_skills_id_seq OWNED BY "InHire".colaborador_skills.id;


--
-- TOC entry 227 (class 1259 OID 95655)
-- Name: colaboradores; Type: TABLE; Schema: InHire; Owner: postgres
--

CREATE TABLE "InHire".colaboradores (
    id bigint NOT NULL,
    nome_abreviado character varying(255) NOT NULL,
    data_admissao timestamp with time zone,
    id_cargo bigint NOT NULL,
    id_senioridade bigint NOT NULL,
    id_step bigint NOT NULL,
    id_vinculo bigint NOT NULL,
    id_modalidade bigint NOT NULL,
    id_setor_empresa bigint,
    id_contrato bigint,
    status boolean DEFAULT true NOT NULL,
    deletado boolean DEFAULT false NOT NULL,
    CONSTRAINT colaboradores_nome_abreviado_check CHECK ((btrim((nome_abreviado)::text) <> ''::text))
);


ALTER TABLE "InHire".colaboradores OWNER TO postgres;

--
-- TOC entry 226 (class 1259 OID 95654)
-- Name: colaboradores_id_seq; Type: SEQUENCE; Schema: InHire; Owner: postgres
--

CREATE SEQUENCE "InHire".colaboradores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "InHire".colaboradores_id_seq OWNER TO postgres;

--
-- TOC entry 3649 (class 0 OID 0)
-- Dependencies: 226
-- Name: colaboradores_id_seq; Type: SEQUENCE OWNED BY; Schema: InHire; Owner: postgres
--

ALTER SEQUENCE "InHire".colaboradores_id_seq OWNED BY "InHire".colaboradores.id;


--
-- TOC entry 225 (class 1259 OID 95634)
-- Name: contratos; Type: TABLE; Schema: InHire; Owner: postgres
--

CREATE TABLE "InHire".contratos (
    id bigint NOT NULL,
    nome_contrato character varying(100) NOT NULL,
    data_inicio date NOT NULL,
    data_termino date NOT NULL,
    id_situacao bigint NOT NULL,
    id_centro_custo bigint NOT NULL,
    id_preposto bigint NOT NULL,
    status boolean DEFAULT true NOT NULL,
    deletado boolean DEFAULT false NOT NULL,
    CONSTRAINT contratos_check CHECK ((data_termino >= data_inicio)),
    CONSTRAINT contratos_nome_contrato_check CHECK ((btrim((nome_contrato)::text) <> ''::text))
);


ALTER TABLE "InHire".contratos OWNER TO postgres;

--
-- TOC entry 224 (class 1259 OID 95633)
-- Name: contratos_id_seq; Type: SEQUENCE; Schema: InHire; Owner: postgres
--

CREATE SEQUENCE "InHire".contratos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "InHire".contratos_id_seq OWNER TO postgres;

--
-- TOC entry 3650 (class 0 OID 0)
-- Dependencies: 224
-- Name: contratos_id_seq; Type: SEQUENCE OWNED BY; Schema: InHire; Owner: postgres
--

ALTER SEQUENCE "InHire".contratos_id_seq OWNED BY "InHire".contratos.id;


--
-- TOC entry 235 (class 1259 OID 95789)
-- Name: demanda_skills; Type: TABLE; Schema: InHire; Owner: postgres
--

CREATE TABLE "InHire".demanda_skills (
    id bigint NOT NULL,
    id_demanda bigint NOT NULL,
    id_skill bigint NOT NULL,
    status boolean DEFAULT true NOT NULL,
    deletado boolean DEFAULT false NOT NULL
);


ALTER TABLE "InHire".demanda_skills OWNER TO postgres;

--
-- TOC entry 234 (class 1259 OID 95788)
-- Name: demanda_skills_id_seq; Type: SEQUENCE; Schema: InHire; Owner: postgres
--

CREATE SEQUENCE "InHire".demanda_skills_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "InHire".demanda_skills_id_seq OWNER TO postgres;

--
-- TOC entry 3651 (class 0 OID 0)
-- Dependencies: 234
-- Name: demanda_skills_id_seq; Type: SEQUENCE OWNED BY; Schema: InHire; Owner: postgres
--

ALTER SEQUENCE "InHire".demanda_skills_id_seq OWNED BY "InHire".demanda_skills.id;


--
-- TOC entry 229 (class 1259 OID 95705)
-- Name: demandas; Type: TABLE; Schema: InHire; Owner: postgres
--

CREATE TABLE "InHire".demandas (
    id bigint NOT NULL,
    nome_demanda character varying(100) NOT NULL,
    id_gerente bigint NOT NULL,
    id_contrato bigint NOT NULL,
    id_tipo_servico bigint NOT NULL,
    id_metodologia bigint,
    id_andamento_demanda bigint NOT NULL,
    id_grupo bigint,
    dt_inicio_demanda date NOT NULL,
    dt_termino_demanda_prevista date NOT NULL,
    compartilha_profissionais boolean DEFAULT false NOT NULL,
    pertence_pmo boolean DEFAULT false NOT NULL,
    status boolean DEFAULT true NOT NULL,
    deletado boolean DEFAULT false NOT NULL,
    CONSTRAINT demandas_check CHECK ((dt_termino_demanda_prevista >= dt_inicio_demanda)),
    CONSTRAINT demandas_nome_demanda_check CHECK ((btrim((nome_demanda)::text) <> ''::text))
);


ALTER TABLE "InHire".demandas OWNER TO postgres;

--
-- TOC entry 228 (class 1259 OID 95704)
-- Name: demandas_id_seq; Type: SEQUENCE; Schema: InHire; Owner: postgres
--

CREATE SEQUENCE "InHire".demandas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "InHire".demandas_id_seq OWNER TO postgres;

--
-- TOC entry 3652 (class 0 OID 0)
-- Dependencies: 228
-- Name: demandas_id_seq; Type: SEQUENCE OWNED BY; Schema: InHire; Owner: postgres
--

ALTER SEQUENCE "InHire".demandas_id_seq OWNED BY "InHire".demandas.id;


--
-- TOC entry 223 (class 1259 OID 95623)
-- Name: dominios; Type: TABLE; Schema: InHire; Owner: postgres
--

CREATE TABLE "InHire".dominios (
    id bigint NOT NULL,
    tipo_dominio character varying(100) NOT NULL,
    valor_dominio character varying(100) NOT NULL,
    descricao character varying(255),
    status boolean DEFAULT true NOT NULL,
    deletado boolean DEFAULT false NOT NULL,
    CONSTRAINT dominios_tipo_dominio_check CHECK ((btrim((tipo_dominio)::text) <> ''::text)),
    CONSTRAINT dominios_valor_dominio_check CHECK ((btrim((valor_dominio)::text) <> ''::text))
);


ALTER TABLE "InHire".dominios OWNER TO postgres;

--
-- TOC entry 222 (class 1259 OID 95622)
-- Name: dominios_id_seq; Type: SEQUENCE; Schema: InHire; Owner: postgres
--

CREATE SEQUENCE "InHire".dominios_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "InHire".dominios_id_seq OWNER TO postgres;

--
-- TOC entry 3653 (class 0 OID 0)
-- Dependencies: 222
-- Name: dominios_id_seq; Type: SEQUENCE OWNED BY; Schema: InHire; Owner: postgres
--

ALTER SEQUENCE "InHire".dominios_id_seq OWNED BY "InHire".dominios.id;


--
-- TOC entry 239 (class 1259 OID 95827)
-- Name: planejamentos; Type: TABLE; Schema: InHire; Owner: postgres
--

CREATE TABLE "InHire".planejamentos (
    id bigint NOT NULL,
    id_alocacao bigint NOT NULL,
    mes character varying(3) NOT NULL,
    ano integer NOT NULL,
    porcentagem integer NOT NULL,
    status boolean DEFAULT true NOT NULL,
    deletado boolean DEFAULT false NOT NULL,
    CONSTRAINT planejamentos_ano_check CHECK (((ano >= 1) AND (ano <= 9999))),
    CONSTRAINT planejamentos_mes_check CHECK (((mes)::text = ANY ((ARRAY['Jan'::character varying, 'Fev'::character varying, 'Mar'::character varying, 'Abr'::character varying, 'Mai'::character varying, 'Jun'::character varying, 'Jul'::character varying, 'Ago'::character varying, 'Set'::character varying, 'Out'::character varying, 'Nov'::character varying, 'Dez'::character varying])::text[]))),
    CONSTRAINT planejamentos_porcentagem_check CHECK (((porcentagem >= 0) AND (porcentagem <= 100)))
);


ALTER TABLE "InHire".planejamentos OWNER TO postgres;

--
-- TOC entry 238 (class 1259 OID 95826)
-- Name: planejamentos_id_seq; Type: SEQUENCE; Schema: InHire; Owner: postgres
--

CREATE SEQUENCE "InHire".planejamentos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "InHire".planejamentos_id_seq OWNER TO postgres;

--
-- TOC entry 3654 (class 0 OID 0)
-- Dependencies: 238
-- Name: planejamentos_id_seq; Type: SEQUENCE OWNED BY; Schema: InHire; Owner: postgres
--

ALTER SEQUENCE "InHire".planejamentos_id_seq OWNED BY "InHire".planejamentos.id;


--
-- TOC entry 231 (class 1259 OID 95748)
-- Name: skills; Type: TABLE; Schema: InHire; Owner: postgres
--

CREATE TABLE "InHire".skills (
    id bigint NOT NULL,
    nome_skill character varying(100) NOT NULL,
    id_area_tecnologia bigint NOT NULL,
    status boolean DEFAULT true NOT NULL,
    deletado boolean DEFAULT false NOT NULL,
    CONSTRAINT skills_nome_skill_check CHECK ((btrim((nome_skill)::text) <> ''::text))
);


ALTER TABLE "InHire".skills OWNER TO postgres;

--
-- TOC entry 230 (class 1259 OID 95747)
-- Name: skills_id_seq; Type: SEQUENCE; Schema: InHire; Owner: postgres
--

CREATE SEQUENCE "InHire".skills_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "InHire".skills_id_seq OWNER TO postgres;

--
-- TOC entry 3655 (class 0 OID 0)
-- Dependencies: 230
-- Name: skills_id_seq; Type: SEQUENCE OWNED BY; Schema: InHire; Owner: postgres
--

ALTER SEQUENCE "InHire".skills_id_seq OWNED BY "InHire".skills.id;


--
-- TOC entry 243 (class 1259 OID 95897)
-- Name: talento_skills; Type: TABLE; Schema: InHire; Owner: postgres
--

CREATE TABLE "InHire".talento_skills (
    id bigint NOT NULL,
    id_talento bigint NOT NULL,
    id_skill bigint NOT NULL,
    id_nivel_conhecimento bigint NOT NULL
);


ALTER TABLE "InHire".talento_skills OWNER TO postgres;

--
-- TOC entry 242 (class 1259 OID 95896)
-- Name: talento_skills_id_seq; Type: SEQUENCE; Schema: InHire; Owner: postgres
--

CREATE SEQUENCE "InHire".talento_skills_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "InHire".talento_skills_id_seq OWNER TO postgres;

--
-- TOC entry 3656 (class 0 OID 0)
-- Dependencies: 242
-- Name: talento_skills_id_seq; Type: SEQUENCE OWNED BY; Schema: InHire; Owner: postgres
--

ALTER SEQUENCE "InHire".talento_skills_id_seq OWNED BY "InHire".talento_skills.id;


--
-- TOC entry 241 (class 1259 OID 95871)
-- Name: talentos; Type: TABLE; Schema: InHire; Owner: postgres
--

CREATE TABLE "InHire".talentos (
    id bigint NOT NULL,
    nome_abreviado character varying(255) NOT NULL,
    id_cargo bigint,
    id_senioridade bigint,
    id_modalidade bigint,
    disponibilidade_informada_percentual integer,
    status boolean DEFAULT true NOT NULL,
    criado_em timestamp with time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    CONSTRAINT talentos_disponibilidade_informada_percentual_check CHECK (((disponibilidade_informada_percentual >= 0) AND (disponibilidade_informada_percentual <= 100))),
    CONSTRAINT talentos_nome_abreviado_check CHECK ((btrim((nome_abreviado)::text) <> ''::text))
);


ALTER TABLE "InHire".talentos OWNER TO postgres;

--
-- TOC entry 240 (class 1259 OID 95870)
-- Name: talentos_id_seq; Type: SEQUENCE; Schema: InHire; Owner: postgres
--

CREATE SEQUENCE "InHire".talentos_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE "InHire".talentos_id_seq OWNER TO postgres;

--
-- TOC entry 3657 (class 0 OID 0)
-- Dependencies: 240
-- Name: talentos_id_seq; Type: SEQUENCE OWNED BY; Schema: InHire; Owner: postgres
--

ALTER SEQUENCE "InHire".talentos_id_seq OWNED BY "InHire".talentos.id;


--
-- TOC entry 244 (class 1259 OID 95925)
-- Name: vw_inconsistencias_dominios; Type: VIEW; Schema: InHire; Owner: postgres
--

CREATE VIEW "InHire".vw_inconsistencias_dominios AS
 WITH referencias AS (
         SELECT 'colaboradores'::text AS tabela,
            c.id AS id_registro,
            v.campo,
            v.id_dominio,
            v.tipo_esperado
           FROM ("InHire".colaboradores c
             CROSS JOIN LATERAL ( VALUES ('id_cargo'::text,c.id_cargo,'CARGO'::text), ('id_senioridade'::text,c.id_senioridade,'SENIORIDADE'::text), ('id_step'::text,c.id_step,'STEP'::text), ('id_vinculo'::text,c.id_vinculo,'VINCULO'::text), ('id_modalidade'::text,c.id_modalidade,'MODALIDADE'::text), ('id_setor_empresa'::text,c.id_setor_empresa,'SETOR_EMPRESA'::text)) v(campo, id_dominio, tipo_esperado))
        UNION ALL
         SELECT 'contratos'::text,
            c.id,
            v.campo,
            v.id_dominio,
            v.tipo_esperado
           FROM ("InHire".contratos c
             CROSS JOIN LATERAL ( VALUES ('id_situacao'::text,c.id_situacao,'SITUACAO_CONTRATO'::text), ('id_centro_custo'::text,c.id_centro_custo,'CENTRO_CUSTO'::text)) v(campo, id_dominio, tipo_esperado))
        UNION ALL
         SELECT 'demandas'::text,
            d_1.id,
            v.campo,
            v.id_dominio,
            v.tipo_esperado
           FROM ("InHire".demandas d_1
             CROSS JOIN LATERAL ( VALUES ('id_tipo_servico'::text,d_1.id_tipo_servico,'TIPO_SERVICO'::text), ('id_metodologia'::text,d_1.id_metodologia,'METODOLOGIA'::text), ('id_andamento_demanda'::text,d_1.id_andamento_demanda,'ANDAMENTO_DEMANDA'::text), ('id_grupo'::text,d_1.id_grupo,'GRUPO'::text)) v(campo, id_dominio, tipo_esperado))
        UNION ALL
         SELECT 'skills'::text,
            skills.id,
            'id_area_tecnologia'::text,
            skills.id_area_tecnologia,
            'AREA_TECNOLOGIA'::text
           FROM "InHire".skills
        UNION ALL
         SELECT 'colaborador_skills'::text,
            colaborador_skills.id,
            'id_nivel_conhecimento'::text,
            colaborador_skills.id_nivel_conhecimento,
            'NIVEL_CONHECIMENTO'::text
           FROM "InHire".colaborador_skills
        UNION ALL
         SELECT 'talentos'::text,
            t.id,
            v.campo,
            v.id_dominio,
            v.tipo_esperado
           FROM ("InHire".talentos t
             CROSS JOIN LATERAL ( VALUES ('id_cargo'::text,t.id_cargo,'CARGO'::text), ('id_senioridade'::text,t.id_senioridade,'SENIORIDADE'::text), ('id_modalidade'::text,t.id_modalidade,'MODALIDADE'::text)) v(campo, id_dominio, tipo_esperado))
        UNION ALL
         SELECT 'talento_skills'::text,
            talento_skills.id,
            'id_nivel_conhecimento'::text,
            talento_skills.id_nivel_conhecimento,
            'NIVEL_CONHECIMENTO'::text
           FROM "InHire".talento_skills
        )
 SELECT r.tabela,
    r.id_registro,
    r.campo,
    r.id_dominio,
    r.tipo_esperado,
    d.tipo_dominio AS tipo_encontrado
   FROM (referencias r
     LEFT JOIN "InHire".dominios d ON ((d.id = r.id_dominio)))
  WHERE ((r.id_dominio IS NOT NULL) AND ((d.tipo_dominio)::text IS DISTINCT FROM r.tipo_esperado));


ALTER VIEW "InHire".vw_inconsistencias_dominios OWNER TO postgres;

--
-- TOC entry 3362 (class 2604 OID 95811)
-- Name: alocacoes id; Type: DEFAULT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".alocacoes ALTER COLUMN id SET DEFAULT nextval('"InHire".alocacoes_id_seq'::regclass);


--
-- TOC entry 3356 (class 2604 OID 95767)
-- Name: colaborador_skills id; Type: DEFAULT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".colaborador_skills ALTER COLUMN id SET DEFAULT nextval('"InHire".colaborador_skills_id_seq'::regclass);


--
-- TOC entry 3345 (class 2604 OID 95658)
-- Name: colaboradores id; Type: DEFAULT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".colaboradores ALTER COLUMN id SET DEFAULT nextval('"InHire".colaboradores_id_seq'::regclass);


--
-- TOC entry 3342 (class 2604 OID 95637)
-- Name: contratos id; Type: DEFAULT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".contratos ALTER COLUMN id SET DEFAULT nextval('"InHire".contratos_id_seq'::regclass);


--
-- TOC entry 3359 (class 2604 OID 95792)
-- Name: demanda_skills id; Type: DEFAULT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".demanda_skills ALTER COLUMN id SET DEFAULT nextval('"InHire".demanda_skills_id_seq'::regclass);


--
-- TOC entry 3348 (class 2604 OID 95708)
-- Name: demandas id; Type: DEFAULT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".demandas ALTER COLUMN id SET DEFAULT nextval('"InHire".demandas_id_seq'::regclass);


--
-- TOC entry 3339 (class 2604 OID 95626)
-- Name: dominios id; Type: DEFAULT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".dominios ALTER COLUMN id SET DEFAULT nextval('"InHire".dominios_id_seq'::regclass);


--
-- TOC entry 3365 (class 2604 OID 95830)
-- Name: planejamentos id; Type: DEFAULT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".planejamentos ALTER COLUMN id SET DEFAULT nextval('"InHire".planejamentos_id_seq'::regclass);


--
-- TOC entry 3353 (class 2604 OID 95751)
-- Name: skills id; Type: DEFAULT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".skills ALTER COLUMN id SET DEFAULT nextval('"InHire".skills_id_seq'::regclass);


--
-- TOC entry 3371 (class 2604 OID 95900)
-- Name: talento_skills id; Type: DEFAULT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".talento_skills ALTER COLUMN id SET DEFAULT nextval('"InHire".talento_skills_id_seq'::regclass);


--
-- TOC entry 3368 (class 2604 OID 95874)
-- Name: talentos id; Type: DEFAULT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".talentos ALTER COLUMN id SET DEFAULT nextval('"InHire".talentos_id_seq'::regclass);


--
-- TOC entry 3635 (class 0 OID 95808)
-- Dependencies: 237
-- Data for Name: alocacoes; Type: TABLE DATA; Schema: InHire; Owner: postgres
--

COPY "InHire".alocacoes (id, id_colaborador, id_demanda, status, deletado) FROM stdin;
1	152	6	f	t
2	124	6	f	t
3	5	6	f	t
4	245	6	f	t
5	212	7	f	t
6	93	2	t	f
7	60	6	f	t
9	70	6	f	t
10	45	6	f	t
11	55	7	t	f
12	170	7	f	t
13	226	6	f	t
15	22	6	f	t
16	100	7	t	f
17	14	4	f	t
18	1	6	f	t
19	127	2	f	t
20	44	6	f	t
21	52	7	t	f
22	63	4	f	t
23	182	6	t	f
24	172	4	t	f
25	154	7	f	t
26	183	4	f	t
28	222	6	f	t
30	123	6	f	t
31	92	6	f	t
32	125	6	f	t
33	188	4	f	t
34	4	6	f	t
35	153	6	f	t
36	200	6	f	t
37	46	6	f	t
39	307	6	t	f
40	208	6	f	t
41	7	4	f	t
42	144	4	f	t
43	103	6	f	t
44	128	4	f	t
45	38	4	f	t
46	229	7	f	t
48	47	4	f	t
49	41	2	t	f
50	202	6	f	t
51	54	4	f	t
52	75	7	t	f
53	105	7	t	f
54	72	2	t	f
55	130	6	f	t
56	240	6	f	t
57	74	2	t	f
58	171	4	f	t
59	231	6	t	f
60	16	4	t	f
61	138	4	f	t
62	242	4	f	t
63	244	6	f	t
64	118	6	t	f
65	88	6	f	t
66	158	6	f	t
67	113	6	f	t
68	9	6	f	t
70	24	6	f	t
71	133	6	f	t
72	150	6	f	t
73	78	6	f	t
74	85	6	f	t
76	32	6	f	t
77	125	4	f	t
78	203	2	f	t
79	111	4	f	t
81	37	6	f	t
82	210	6	f	t
83	108	6	f	t
84	147	6	f	t
85	21	1	t	f
86	140	7	f	t
87	15	7	t	f
88	107	6	f	t
90	3	6	f	t
91	43	6	f	t
92	205	6	f	t
93	234	7	f	t
94	71	7	t	f
95	11	4	f	t
96	86	2	t	f
97	51	4	f	t
98	196	6	f	t
99	31	4	f	t
100	136	6	t	f
101	17	4	f	t
102	131	1	f	t
103	50	4	f	t
104	34	7	t	f
105	126	3	f	t
106	40	2	t	f
107	214	6	f	t
109	167	4	f	t
110	33	7	t	f
111	10	4	f	t
112	73	2	t	f
113	119	6	f	t
114	29	1	t	f
115	99	6	f	t
116	48	6	f	t
117	28	6	f	t
118	42	4	f	t
119	134	4	f	t
120	83	2	t	f
121	177	4	f	t
122	80	6	f	t
123	239	3	f	t
124	227	2	f	t
125	163	4	f	t
126	120	6	t	f
128	102	6	f	t
129	6	6	f	t
131	159	6	f	t
132	207	6	f	t
133	155	7	f	t
134	217	2	f	t
135	84	6	f	t
136	145	6	f	t
137	106	1	t	f
138	168	7	f	t
139	98	6	f	t
140	243	6	f	t
141	90	6	f	t
142	18	6	f	t
143	114	3	t	f
144	59	6	f	t
146	219	6	f	t
147	81	6	f	t
148	162	4	f	t
149	79	6	f	t
150	76	6	f	t
151	69	6	f	t
153	142	6	f	t
154	95	7	t	f
155	82	4	f	t
158	149	4	f	t
159	61	2	t	f
160	87	2	t	f
162	197	4	f	t
163	132	6	f	t
164	194	6	f	t
165	135	6	t	f
166	191	6	f	t
167	275	1	t	f
168	247	1	t	f
169	273	6	f	t
170	66	4	t	f
171	2	11	f	t
172	243	1	t	f
173	19	1	t	f
174	266	1	t	f
175	220	4	t	f
176	68	4	f	t
177	122	4	f	t
178	97	4	f	t
179	20	11	t	f
180	242	11	t	f
181	30	11	t	f
182	249	11	t	f
183	250	11	t	f
184	62	11	t	f
185	257	6	t	f
186	66	11	t	f
187	68	11	t	f
188	84	14	t	f
189	130	14	f	t
190	104	14	t	f
191	94	12	f	t
192	97	11	t	f
193	97	13	t	f
194	94	11	t	f
195	110	11	f	t
196	110	15	f	t
197	263	16	f	t
198	263	6	f	t
199	130	16	t	f
200	130	6	f	t
201	264	4	f	t
202	264	15	t	f
203	122	11	t	f
204	124	11	f	t
205	128	16	t	f
206	128	6	t	f
207	182	16	t	f
208	188	11	t	f
209	194	11	t	f
210	198	4	t	f
211	212	16	t	f
212	277	16	t	f
213	277	6	t	f
214	96	16	t	f
215	96	6	t	f
216	241	16	t	f
217	235	16	t	f
218	235	6	t	f
219	36	4	f	t
220	53	4	t	f
221	60	4	f	t
222	70	4	f	t
223	101	4	f	t
224	126	4	f	t
225	133	4	f	t
226	140	4	f	t
227	142	4	t	f
228	143	4	f	t
229	148	4	f	t
230	160	4	t	f
231	168	4	f	t
232	174	4	f	t
233	191	4	f	t
234	203	4	f	t
235	221	4	f	t
236	228	4	f	t
237	207	2	t	f
238	208	2	t	f
239	224	2	t	f
240	237	2	t	f
241	203	2	f	t
242	131	2	t	f
243	134	2	f	t
244	199	2	t	f
245	274	5	t	f
246	276	5	t	f
247	240	5	t	f
248	140	7	f	t
249	92	7	t	f
250	162	7	t	f
251	167	7	t	f
252	169	7	t	f
253	185	7	t	f
254	197	7	t	f
255	210	7	t	f
256	218	7	t	f
257	239	7	t	f
258	140	3	f	t
259	154	16	f	t
260	154	6	f	t
261	155	4	t	f
262	7	3	f	t
263	10	3	f	t
264	11	3	f	t
265	14	3	f	t
266	31	3	f	t
267	36	3	f	t
268	38	3	f	t
269	248	3	t	f
270	42	3	f	t
271	47	3	f	t
272	50	3	f	t
273	51	3	f	t
274	251	3	t	f
275	259	3	t	f
276	265	3	f	t
277	129	3	t	f
278	267	3	f	t
279	270	3	t	f
280	271	3	t	f
281	159	3	t	f
282	163	3	t	f
283	225	3	t	f
284	7	4	f	t
285	10	4	f	t
286	11	4	f	t
287	14	4	f	t
288	31	4	f	t
289	36	4	t	f
290	38	4	f	t
291	42	4	f	t
292	47	4	f	t
293	50	4	f	t
294	51	4	f	t
295	140	4	f	t
296	3	8	t	f
297	5	8	t	f
298	6	8	t	f
299	18	8	t	f
300	24	8	t	f
301	28	8	t	f
302	246	8	t	f
303	43	8	t	f
304	46	8	t	f
305	48	8	t	f
306	49	8	t	f
307	254	8	t	f
308	59	8	t	f
309	76	8	t	f
310	77	8	t	f
311	78	8	t	f
312	79	8	t	f
313	153	8	t	f
314	152	8	f	t
315	147	8	t	f
316	150	8	t	f
317	158	8	t	f
318	273	8	t	f
319	170	8	t	f
320	179	8	t	f
321	181	8	t	f
322	190	8	t	f
323	191	8	f	t
324	196	8	t	f
325	211	8	t	f
326	213	8	t	f
327	219	8	t	f
328	222	8	t	f
329	226	8	t	f
330	229	8	t	f
331	4	17	t	f
332	9	17	t	f
333	22	17	t	f
334	32	17	t	f
335	37	17	t	f
336	44	17	t	f
337	45	17	t	f
338	69	17	t	f
339	88	17	t	f
340	98	17	t	f
341	127	17	t	f
342	132	17	t	f
343	134	17	t	f
344	152	17	t	f
345	156	17	t	f
346	154	17	t	f
347	177	17	t	f
348	183	17	t	f
349	200	17	t	f
350	205	17	t	f
351	217	17	t	f
352	227	17	t	f
353	233	17	t	f
354	240	17	t	f
355	209	17	t	f
356	1	17	t	f
357	214	17	t	f
358	99	17	t	f
359	35	8	t	f
360	256	1	t	f
361	258	18	t	f
362	261	8	t	f
363	262	16	t	f
364	117	5	t	f
365	268	1	t	f
366	269	11	t	f
367	146	7	t	f
368	151	8	t	f
369	173	8	t	f
370	278	11	t	f
371	253	19	t	f
372	260	20	t	f
373	272	20	t	f
374	137	20	t	f
375	291	11	f	t
376	110	16	f	t
377	110	6	t	f
378	290	8	t	f
379	23	21	t	f
380	27	22	t	f
381	284	1	f	t
382	285	1	t	f
383	288	7	t	f
384	286	8	f	t
385	286	7	t	f
386	287	8	f	t
387	289	7	t	f
388	182	4	t	f
389	287	7	t	f
390	123	7	t	f
391	149	7	t	f
392	292	4	f	t
393	293	7	t	f
394	294	7	t	f
395	295	7	t	f
396	124	5	f	t
397	97	6	t	f
398	250	25	t	f
399	250	13	t	f
400	242	25	t	f
401	68	25	t	f
402	94	25	t	f
403	188	25	t	f
404	124	16	f	t
405	128	11	t	f
406	138	8	t	f
407	145	8	t	f
408	171	8	t	f
409	103	8	t	f
410	102	8	t	f
411	107	8	t	f
412	108	8	t	f
413	113	8	t	f
414	307	8	t	f
415	308	11	t	f
416	250	23	t	f
417	250	14	t	f
418	250	26	t	f
419	308	25	t	f
420	97	25	t	f
421	124	6	t	f
422	188	23	t	f
423	234	4	t	f
424	306	1	t	f
425	297	2	t	f
426	298	2	t	f
427	302	2	t	f
428	304	2	t	f
429	299	2	t	f
430	303	2	t	f
431	305	7	t	f
432	104	21	t	f
433	278	4	f	t
434	259	5	t	f
435	101	32	t	f
436	101	33	t	f
437	101	42	t	f
438	101	27	t	f
439	220	36	t	f
440	220	30	t	f
441	220	42	t	f
442	292	27	t	f
443	148	28	t	f
444	148	30	t	f
445	148	42	t	f
446	278	27	t	f
447	191	27	t	f
448	174	32	t	f
449	174	33	t	f
450	174	34	t	f
451	174	27	t	f
452	174	28	t	f
453	143	33	t	f
454	143	34	t	f
455	84	26	t	f
456	309	7	t	f
457	310	17	t	f
458	311	17	t	f
459	2	13	f	t
460	300	11	t	f
461	231	1	t	f
462	301	1	t	f
463	119	1	f	t
464	136	1	t	f
465	17	38	f	t
466	17	4	f	t
467	291	20	t	f
468	20	6	t	f
469	242	26	t	f
470	68	26	t	f
471	2	80	t	f
472	30	80	t	f
473	188	80	t	f
474	278	80	t	f
475	2	82	f	t
476	319	84	t	f
477	322	84	t	f
478	318	84	t	f
479	320	84	t	f
480	317	7	t	f
481	313	1	t	f
482	315	1	t	f
483	314	1	t	f
484	135	2	t	f
485	296	1	t	f
486	63	38	t	f
487	312	7	t	f
488	140	38	t	f
489	321	38	t	f
490	94	80	t	f
491	122	80	t	f
492	326	1	t	f
493	327	1	t	f
494	249	80	t	f
495	68	80	t	f
496	284	11	t	f
497	160	27	t	f
498	143	27	t	f
499	203	4	t	f
500	203	36	t	f
501	203	27	t	f
502	292	83	t	f
503	17	32	t	f
504	17	35	t	f
505	17	86	t	f
506	17	27	t	f
507	53	37	t	f
508	53	86	t	f
509	53	30	t	f
510	51	86	t	f
511	51	39	t	f
512	51	27	t	f
513	70	83	t	f
514	70	29	t	f
515	16	86	t	f
516	16	41	t	f
517	16	27	t	f
518	16	31	t	f
519	66	36	t	f
520	198	27	t	f
521	264	41	t	f
522	182	36	t	f
523	182	27	t	f
524	96	35	t	f
525	96	33	t	f
526	124	80	t	f
527	119	80	t	f
528	97	80	t	f
529	194	80	t	f
530	270	65	t	f
531	270	54	t	f
532	270	82	t	f
533	159	82	t	f
534	159	62	t	f
535	159	63	t	f
536	248	65	t	f
537	248	5	t	f
538	248	57	t	f
539	225	82	t	f
540	225	59	t	f
541	271	66	t	f
542	271	82	t	f
543	271	5	t	f
544	271	75	t	f
545	271	76	t	f
546	271	77	t	f
547	114	65	t	f
548	114	53	t	f
549	265	82	t	f
550	265	62	t	f
551	265	63	t	f
552	163	82	t	f
553	163	53	t	f
554	163	54	t	f
555	129	53	t	f
556	129	74	t	f
557	7	108	t	f
558	10	108	t	f
559	11	108	t	f
560	14	108	t	f
561	31	108	t	f
562	38	108	t	f
563	42	108	t	f
564	47	108	t	f
565	50	108	t	f
566	51	108	t	f
567	54	108	t	f
568	60	108	t	f
569	63	108	t	f
570	82	108	t	f
571	111	108	t	f
572	125	108	t	f
573	126	108	t	f
574	133	108	t	f
575	140	108	t	f
576	144	108	t	f
577	168	108	t	f
578	221	108	t	f
579	228	108	t	f
580	242	14	f	t
581	242	14	f	t
582	85	8	t	f
583	90	8	t	f
584	70	119	t	f
585	96	118	t	f
586	96	119	t	f
587	51	118	t	f
588	53	118	t	f
589	53	108	t	f
590	143	87	t	f
591	220	87	t	f
592	203	86	t	f
593	160	87	t	f
594	198	33	t	f
595	198	87	t	f
596	16	118	t	f
597	16	87	t	f
598	16	119	t	f
599	242	80	t	f
600	198	36	t	f
601	66	30	t	f
602	263	120	t	f
603	263	121	t	f
604	212	6	t	f
605	110	121	t	f
606	262	120	t	f
607	331	6	t	f
608	331	120	t	f
609	2	122	t	f
610	2	123	t	f
611	263	122	t	f
612	263	123	t	f
613	119	122	t	f
614	119	123	t	f
615	265	122	t	f
616	265	123	f	t
617	188	122	t	f
618	225	122	t	f
619	130	122	t	f
620	163	122	t	f
621	163	123	t	f
622	278	123	t	f
623	124	120	t	f
624	124	123	t	f
625	284	123	t	f
626	119	120	t	f
627	235	120	t	f
628	267	123	t	f
629	267	122	t	f
630	250	80	t	f
631	250	120	t	f
632	250	122	t	f
633	250	123	t	f
634	250	126	t	f
635	84	126	t	f
\.


--
-- TOC entry 3631 (class 0 OID 95764)
-- Dependencies: 233
-- Data for Name: colaborador_skills; Type: TABLE DATA; Schema: InHire; Owner: postgres
--

COPY "InHire".colaborador_skills (id, id_colaborador, id_skill, nivel_conhecimento, id_nivel_conhecimento, status, deletado) FROM stdin;
1	140	2	INTERMEDIARIO	320	t	f
954	17	26	INTERMEDIARIO	320	t	f
955	17	16	INTERMEDIARIO	320	t	f
956	17	85	BASICO	318	t	f
957	17	53	AVANCADO	321	t	f
958	269	60	BASICO	318	t	f
959	269	16	BASICO	318	t	f
960	269	53	BASICO	318	t	f
961	286	59	AVANCADO	321	t	f
962	286	21	AVANCADO	321	t	f
963	286	38	AVANCADO	321	t	f
964	286	19	AVANCADO	321	t	f
965	286	58	AVANCADO	321	t	f
966	286	56	AVANCADO	321	t	f
967	286	117	AVANCADO	321	t	f
968	286	115	AVANCADO	321	t	f
969	286	65	AVANCADO	321	t	f
970	286	14	AVANCADO	321	t	f
971	286	55	AVANCADO	321	t	f
972	286	45	AVANCADO	321	t	f
973	284	26	AVANCADO	321	t	f
974	284	21	INTERMEDIARIO	320	t	f
975	284	36	INTERMEDIARIO	320	t	f
976	284	58	INTERMEDIARIO	320	t	f
977	284	16	AVANCADO	321	t	f
978	287	60	INTERMEDIARIO	320	t	f
979	287	59	INTERMEDIARIO	320	t	f
980	287	35	INTERMEDIARIO	320	t	f
981	287	120	INTERMEDIARIO	320	t	f
982	287	118	INTERMEDIARIO	320	t	f
983	287	117	AVANCADO	321	t	f
984	287	115	AVANCADO	321	t	f
985	287	14	AVANCADO	321	t	f
986	242	61	BASICO	318	t	f
987	242	16	BASICO	318	t	f
988	242	53	BASICO	318	t	f
989	263	62	INTERMEDIARIO	320	t	f
990	263	59	AVANCADO	321	t	f
991	263	23	AVANCADO	321	t	f
992	263	41	AVANCADO	321	t	f
993	263	38	AVANCADO	321	t	f
994	263	19	AVANCADO	321	t	f
995	263	34	AVANCADO	321	t	f
996	263	119	AVANCADO	321	t	f
997	263	69	INTERMEDIARIO	320	t	f
998	263	50	AVANCADO	321	t	f
999	263	84	AVANCADO	321	t	f
1000	263	64	AVANCADO	321	t	f
1001	263	53	AVANCADO	321	t	f
1002	263	63	INTERMEDIARIO	320	t	f
1003	277	50	BASICO	318	t	f
1004	278	59	AVANCADO	321	t	f
1005	278	20	INTERMEDIARIO	320	t	f
1006	278	16	AVANCADO	321	t	f
1007	248	62	AVANCADO	321	t	f
1008	248	61	AVANCADO	321	t	f
1009	248	106	AVANCADO	321	t	f
1010	248	26	INTERMEDIARIO	320	t	f
1011	248	60	AVANCADO	321	t	f
1012	248	59	AVANCADO	321	t	f
1013	248	38	INTERMEDIARIO	320	t	f
1014	248	19	AVANCADO	321	t	f
1015	248	36	INTERMEDIARIO	320	t	f
1016	248	34	INTERMEDIARIO	320	t	f
1017	248	33	INTERMEDIARIO	320	t	f
1018	248	18	AVANCADO	321	t	f
1019	248	102	AVANCADO	321	t	f
1020	248	120	AVANCADO	321	t	f
1021	248	119	AVANCADO	321	t	f
1022	248	50	AVANCADO	321	t	f
1023	248	65	INTERMEDIARIO	320	t	f
1024	248	98	INTERMEDIARIO	320	t	f
1025	248	83	INTERMEDIARIO	320	t	f
1026	248	53	BASICO	318	t	f
1027	251	62	AVANCADO	321	t	f
1028	251	61	AVANCADO	321	t	f
1029	251	106	INTERMEDIARIO	320	t	f
1030	251	11	INTERMEDIARIO	320	t	f
1031	251	26	BASICO	318	t	f
1032	251	43	BASICO	318	t	f
1033	251	59	AVANCADO	321	t	f
1034	251	41	INTERMEDIARIO	320	t	f
1035	251	38	INTERMEDIARIO	320	t	f
1036	251	19	INTERMEDIARIO	320	t	f
1037	251	36	INTERMEDIARIO	320	t	f
1038	251	33	BASICO	318	t	f
1039	251	18	INTERMEDIARIO	320	t	f
1040	251	102	INTERMEDIARIO	320	t	f
1041	251	120	INTERMEDIARIO	320	t	f
1042	251	119	INTERMEDIARIO	320	t	f
1043	251	117	INTERMEDIARIO	320	t	f
1044	251	50	BASICO	318	t	f
1045	251	65	BASICO	318	t	f
1046	253	103	BASICO	318	t	f
1047	253	119	BASICO	318	t	f
1048	253	50	BASICO	318	t	f
1049	253	64	BASICO	318	t	f
1050	259	62	AVANCADO	321	t	f
1051	259	61	AVANCADO	321	t	f
1052	259	106	AVANCADO	321	t	f
1053	259	26	AVANCADO	321	t	f
1054	259	60	AVANCADO	321	t	f
1055	259	38	BASICO	318	t	f
1056	259	19	AVANCADO	321	t	f
1057	259	36	INTERMEDIARIO	320	t	f
1058	259	34	INTERMEDIARIO	320	t	f
1059	259	33	AVANCADO	321	t	f
1060	259	35	INTERMEDIARIO	320	t	f
1061	259	18	AVANCADO	321	t	f
1062	259	102	INTERMEDIARIO	320	t	f
1063	259	122	INTERMEDIARIO	320	t	f
1064	259	120	INTERMEDIARIO	320	t	f
1065	259	119	INTERMEDIARIO	320	t	f
1066	259	65	AVANCADO	321	t	f
1067	259	98	BASICO	318	t	f
1068	262	59	INTERMEDIARIO	320	t	f
1069	262	53	AVANCADO	321	t	f
1070	265	106	AVANCADO	321	t	f
1071	265	26	AVANCADO	321	t	f
1072	265	92	INTERMEDIARIO	320	t	f
1073	265	41	AVANCADO	321	t	f
1074	265	38	AVANCADO	321	t	f
1075	265	19	INTERMEDIARIO	320	t	f
1076	265	36	AVANCADO	321	t	f
1077	265	34	INTERMEDIARIO	320	t	f
1078	265	7	AVANCADO	321	t	f
1079	265	18	AVANCADO	321	t	f
1080	265	102	INTERMEDIARIO	320	t	f
1081	265	57	BASICO	318	t	f
1082	265	119	INTERMEDIARIO	320	t	f
1083	265	30	INTERMEDIARIO	320	t	f
1084	265	50	INTERMEDIARIO	320	t	f
1085	265	28	AVANCADO	321	t	f
1086	265	84	INTERMEDIARIO	320	t	f
1087	265	53	AVANCADO	321	t	f
1088	266	59	BASICO	318	t	f
1089	266	21	BASICO	318	t	f
1090	266	19	BASICO	318	t	f
1091	266	58	BASICO	318	t	f
1092	266	16	BASICO	318	t	f
1093	266	56	BASICO	318	t	f
1094	266	65	BASICO	318	t	f
1095	266	55	BASICO	318	t	f
1096	268	61	BASICO	318	t	f
1097	268	94	BASICO	318	t	f
1098	268	41	BASICO	318	t	f
1099	268	89	BASICO	318	t	f
1100	268	36	BASICO	318	t	f
1101	268	122	BASICO	318	t	f
1102	268	115	BASICO	318	t	f
1103	268	65	BASICO	318	t	f
1104	268	64	BASICO	318	t	f
1105	270	103	INTERMEDIARIO	320	t	f
1106	270	119	BASICO	318	t	f
1107	270	50	INTERMEDIARIO	320	t	f
1108	270	64	BASICO	318	t	f
1109	257	59	BASICO	318	t	f
1110	257	41	BASICO	318	t	f
1111	257	19	BASICO	318	t	f
1112	257	34	BASICO	318	t	f
1113	257	16	BASICO	318	t	f
1114	257	119	BASICO	318	t	f
1115	257	64	BASICO	318	t	f
1116	257	53	BASICO	318	t	f
1117	257	63	BASICO	318	t	f
1118	271	62	INTERMEDIARIO	320	t	f
1119	271	106	INTERMEDIARIO	320	t	f
1120	271	27	BASICO	318	t	f
1121	271	10	AVANCADO	321	t	f
1122	271	21	INTERMEDIARIO	320	t	f
1123	271	22	BASICO	318	t	f
1124	271	41	AVANCADO	321	t	f
1125	271	20	AVANCADO	321	t	f
1126	271	38	AVANCADO	321	t	f
1127	271	36	INTERMEDIARIO	320	t	f
1128	271	103	INTERMEDIARIO	320	t	f
1129	271	33	INTERMEDIARIO	320	t	f
1130	271	9	INTERMEDIARIO	320	t	f
1131	271	35	INTERMEDIARIO	320	t	f
1132	271	18	INTERMEDIARIO	320	t	f
1133	271	17	BASICO	318	t	f
1134	271	102	INTERMEDIARIO	320	t	f
1135	271	58	AVANCADO	321	t	f
1136	271	16	BASICO	318	t	f
1137	271	32	INTERMEDIARIO	320	t	f
1138	271	69	BASICO	318	t	f
1139	271	5	AVANCADO	321	t	f
1140	271	67	INTERMEDIARIO	320	t	f
1141	271	65	INTERMEDIARIO	320	t	f
1142	271	101	INTERMEDIARIO	320	t	f
1143	271	53	INTERMEDIARIO	320	t	f
1144	244	58	BASICO	318	t	f
1145	244	16	BASICO	318	t	f
1146	244	56	BASICO	318	t	f
1147	244	55	BASICO	318	t	f
1148	244	53	BASICO	318	t	f
1149	264	60	AVANCADO	321	t	f
1150	264	59	AVANCADO	321	t	f
1151	264	21	INTERMEDIARIO	320	t	f
1152	264	41	INTERMEDIARIO	320	t	f
1153	264	20	INTERMEDIARIO	320	t	f
1154	264	19	AVANCADO	321	t	f
1155	264	36	BASICO	318	t	f
1156	264	18	INTERMEDIARIO	320	t	f
1157	264	58	AVANCADO	321	t	f
1158	264	16	INTERMEDIARIO	320	t	f
1159	264	56	AVANCADO	321	t	f
1160	264	116	AVANCADO	321	t	f
1161	264	115	AVANCADO	321	t	f
1162	264	50	BASICO	318	t	f
1163	264	65	BASICO	318	t	f
1164	264	55	AVANCADO	321	t	f
1165	264	64	INTERMEDIARIO	320	t	f
1166	264	53	INTERMEDIARIO	320	t	f
1167	2	103	AVANCADO	321	t	f
1168	2	119	INTERMEDIARIO	320	t	f
1169	2	50	INTERMEDIARIO	320	t	f
1170	2	64	BASICO	318	t	f
1171	16	82	AVANCADO	321	t	f
1172	16	81	INTERMEDIARIO	320	t	f
1173	16	61	AVANCADO	321	t	f
1174	16	26	AVANCADO	321	t	f
1175	16	95	INTERMEDIARIO	320	t	f
1176	16	42	INTERMEDIARIO	320	t	f
1177	16	59	AVANCADO	321	t	f
1178	16	23	INTERMEDIARIO	320	t	f
1179	16	90	AVANCADO	321	t	f
1180	16	77	INTERMEDIARIO	320	t	f
1181	16	41	INTERMEDIARIO	320	t	f
1182	16	76	AVANCADO	321	t	f
1183	16	20	AVANCADO	321	t	f
1184	16	19	AVANCADO	321	t	f
1185	16	36	INTERMEDIARIO	320	t	f
1186	16	74	AVANCADO	321	t	f
1187	16	35	INTERMEDIARIO	320	t	f
1188	16	73	AVANCADO	321	t	f
1189	16	18	AVANCADO	321	t	f
1190	16	110	AVANCADO	321	t	f
1191	16	88	INTERMEDIARIO	320	t	f
1192	16	58	AVANCADO	321	t	f
1193	16	16	AVANCADO	321	t	f
1194	16	87	INTERMEDIARIO	320	t	f
1195	16	56	AVANCADO	321	t	f
1196	16	115	AVANCADO	321	t	f
1197	16	69	INTERMEDIARIO	320	t	f
1198	16	67	AVANCADO	321	t	f
1199	16	66	AVANCADO	321	t	f
1200	16	65	AVANCADO	321	t	f
1201	16	55	AVANCADO	321	t	f
1202	16	53	AVANCADO	321	t	f
1203	16	63	INTERMEDIARIO	320	t	f
1204	19	26	BASICO	318	t	f
1205	19	59	BASICO	318	t	f
1206	19	41	BASICO	318	t	f
1207	19	20	BASICO	318	t	f
1208	19	18	BASICO	318	t	f
1209	20	53	BASICO	318	t	f
1210	53	61	AVANCADO	321	t	f
1211	53	59	AVANCADO	321	t	f
1212	53	21	INTERMEDIARIO	320	t	f
1213	53	41	AVANCADO	321	t	f
1214	53	19	AVANCADO	321	t	f
1215	53	36	INTERMEDIARIO	320	t	f
1216	53	18	AVANCADO	321	t	f
1217	53	86	AVANCADO	321	t	f
1218	53	58	AVANCADO	321	t	f
1219	53	56	AVANCADO	321	t	f
1220	53	15	AVANCADO	321	t	f
1221	53	66	AVANCADO	321	t	f
1222	53	65	AVANCADO	321	t	f
1223	53	55	AVANCADO	321	t	f
1224	101	41	BASICO	318	t	f
1225	101	37	BASICO	318	t	f
1226	101	36	BASICO	318	t	f
1227	101	31	BASICO	318	t	f
1228	101	6	BASICO	318	t	f
1229	101	29	BASICO	318	t	f
1230	101	47	BASICO	318	t	f
1231	101	3	BASICO	318	t	f
1232	124	50	AVANCADO	321	t	f
1233	129	62	INTERMEDIARIO	320	t	f
1234	129	61	INTERMEDIARIO	320	t	f
1235	129	106	AVANCADO	321	t	f
1236	129	26	BASICO	318	t	f
1237	129	60	INTERMEDIARIO	320	t	f
1238	129	59	INTERMEDIARIO	320	t	f
1239	129	41	AVANCADO	321	t	f
1240	129	20	AVANCADO	321	t	f
1241	129	38	INTERMEDIARIO	320	t	f
1242	129	111	INTERMEDIARIO	320	t	f
1243	129	19	INTERMEDIARIO	320	t	f
1244	129	36	AVANCADO	321	t	f
1245	129	34	BASICO	318	t	f
1246	129	33	BASICO	318	t	f
1247	129	18	AVANCADO	321	t	f
1248	129	102	INTERMEDIARIO	320	t	f
1249	129	109	INTERMEDIARIO	320	t	f
1250	129	108	BASICO	318	t	f
1251	129	56	AVANCADO	321	t	f
1252	129	120	INTERMEDIARIO	320	t	f
1253	129	119	AVANCADO	321	t	f
1254	129	65	INTERMEDIARIO	320	t	f
1255	129	55	AVANCADO	321	t	f
1256	129	98	BASICO	318	t	f
1257	129	83	BASICO	318	t	f
1258	129	53	BASICO	318	t	f
1259	148	59	INTERMEDIARIO	320	t	f
1260	148	40	INTERMEDIARIO	320	t	f
1261	148	20	INTERMEDIARIO	320	t	f
1262	148	36	BASICO	318	t	f
1263	148	18	INTERMEDIARIO	320	t	f
1264	148	58	INTERMEDIARIO	320	t	f
1265	148	115	INTERMEDIARIO	320	t	f
1266	148	53	INTERMEDIARIO	320	t	f
1267	154	43	AVANCADO	321	t	f
1268	154	21	INTERMEDIARIO	320	t	f
1269	154	35	INTERMEDIARIO	320	t	f
1270	163	62	AVANCADO	321	t	f
1271	163	97	AVANCADO	321	t	f
1272	163	61	AVANCADO	321	t	f
1273	163	106	AVANCADO	321	t	f
1274	163	60	AVANCADO	321	t	f
1275	163	59	INTERMEDIARIO	320	t	f
1276	163	41	INTERMEDIARIO	320	t	f
1277	163	89	AVANCADO	321	t	f
1278	163	105	AVANCADO	321	t	f
1279	163	38	INTERMEDIARIO	320	t	f
1280	163	19	INTERMEDIARIO	320	t	f
1281	163	8	INTERMEDIARIO	320	t	f
1282	163	7	INTERMEDIARIO	320	t	f
1283	163	18	INTERMEDIARIO	320	t	f
1284	163	102	AVANCADO	321	t	f
1285	163	120	AVANCADO	321	t	f
1286	163	119	AVANCADO	321	t	f
1287	163	118	AVANCADO	321	t	f
1288	163	85	AVANCADO	321	t	f
1289	163	30	AVANCADO	321	t	f
1290	163	65	INTERMEDIARIO	320	t	f
1291	163	84	AVANCADO	321	t	f
1292	163	4	BASICO	318	t	f
1293	163	83	AVANCADO	321	t	f
1294	163	53	INTERMEDIARIO	320	t	f
1295	174	61	AVANCADO	321	t	f
1296	174	59	AVANCADO	321	t	f
1297	174	19	INTERMEDIARIO	320	t	f
1298	155	59	BASICO	318	t	f
1299	155	41	BASICO	318	t	f
1300	155	19	BASICO	318	t	f
1301	155	35	BASICO	318	t	f
1302	191	26	AVANCADO	321	t	f
1303	191	60	AVANCADO	321	t	f
1304	191	59	AVANCADO	321	t	f
1305	191	21	INTERMEDIARIO	320	t	f
1306	191	41	AVANCADO	321	t	f
1307	191	20	AVANCADO	321	t	f
1308	191	36	AVANCADO	321	t	f
1309	191	34	AVANCADO	321	t	f
1310	191	18	AVANCADO	321	t	f
1311	191	16	INTERMEDIARIO	320	t	f
1312	191	65	AVANCADO	321	t	f
1313	202	106	AVANCADO	321	t	f
1314	202	105	AVANCADO	321	t	f
1315	202	38	BASICO	318	t	f
1316	202	103	AVANCADO	321	t	f
1317	202	35	BASICO	318	t	f
1318	203	42	BASICO	318	t	f
1319	203	59	BASICO	318	t	f
1320	203	21	BASICO	318	t	f
1321	203	41	BASICO	318	t	f
1322	203	20	BASICO	318	t	f
1323	203	19	BASICO	318	t	f
1324	203	36	BASICO	318	t	f
1325	203	18	BASICO	318	t	f
1326	203	56	BASICO	318	t	f
1327	203	119	BASICO	318	t	f
1328	203	117	BASICO	318	t	f
1329	203	115	BASICO	318	t	f
1330	203	66	BASICO	318	t	f
1331	203	65	BASICO	318	t	f
1332	203	55	BASICO	318	t	f
1333	220	106	INTERMEDIARIO	320	t	f
1334	220	96	INTERMEDIARIO	320	t	f
1335	220	41	INTERMEDIARIO	320	t	f
1336	220	36	INTERMEDIARIO	320	t	f
1337	220	58	BASICO	318	t	f
1338	220	56	BASICO	318	t	f
1339	220	115	INTERMEDIARIO	320	t	f
1340	220	50	INTERMEDIARIO	320	t	f
1341	220	49	INTERMEDIARIO	320	t	f
1342	220	65	BASICO	318	t	f
1343	220	29	INTERMEDIARIO	320	t	f
1344	220	84	INTERMEDIARIO	320	t	f
1345	220	55	BASICO	318	t	f
1346	68	64	BASICO	318	t	f
1347	84	26	INTERMEDIARIO	320	t	f
1348	84	19	INTERMEDIARIO	320	t	f
1349	84	16	INTERMEDIARIO	320	t	f
1350	96	102	AVANCADO	321	t	f
1351	104	61	AVANCADO	321	t	f
1352	104	59	AVANCADO	321	t	f
1353	104	19	INTERMEDIARIO	320	t	f
1354	104	72	AVANCADO	321	t	f
1355	104	58	AVANCADO	321	t	f
1356	104	16	BASICO	318	t	f
1357	104	56	AVANCADO	321	t	f
1358	104	115	AVANCADO	321	t	f
1359	104	55	AVANCADO	321	t	f
1360	104	113	AVANCADO	321	t	f
1361	104	64	BASICO	318	t	f
1362	128	98	INTERMEDIARIO	320	t	f
1363	130	61	AVANCADO	321	t	f
1364	130	59	INTERMEDIARIO	320	t	f
1365	130	41	AVANCADO	321	t	f
1366	130	19	AVANCADO	321	t	f
1367	130	58	AVANCADO	321	t	f
1368	130	56	INTERMEDIARIO	320	t	f
1369	130	115	AVANCADO	321	t	f
1370	130	15	AVANCADO	321	t	f
1371	130	65	INTERMEDIARIO	320	t	f
1372	130	55	INTERMEDIARIO	320	t	f
1373	212	21	AVANCADO	321	t	f
1374	77	58	BASICO	318	t	f
1375	77	16	BASICO	318	t	f
1376	77	56	BASICO	318	t	f
1377	77	55	BASICO	318	t	f
1378	114	62	INTERMEDIARIO	320	t	f
1379	114	61	INTERMEDIARIO	320	t	f
1380	114	106	AVANCADO	321	t	f
1381	114	60	INTERMEDIARIO	320	t	f
1382	114	59	AVANCADO	321	t	f
1383	114	38	INTERMEDIARIO	320	t	f
1384	114	36	INTERMEDIARIO	320	t	f
1385	114	34	BASICO	318	t	f
1386	114	33	INTERMEDIARIO	320	t	f
1387	114	35	AVANCADO	321	t	f
1388	114	102	INTERMEDIARIO	320	t	f
1389	114	58	INTERMEDIARIO	320	t	f
1390	114	120	INTERMEDIARIO	320	t	f
1391	114	119	AVANCADO	321	t	f
1392	114	65	AVANCADO	321	t	f
1393	114	98	INTERMEDIARIO	320	t	f
1394	114	83	BASICO	318	t	f
1395	114	53	AVANCADO	321	t	f
1396	225	62	BASICO	318	t	f
1397	225	61	AVANCADO	321	t	f
1398	225	106	BASICO	318	t	f
1399	225	60	BASICO	318	t	f
1400	225	59	AVANCADO	321	t	f
1401	225	20	INTERMEDIARIO	320	t	f
1402	225	38	INTERMEDIARIO	320	t	f
1403	225	19	AVANCADO	321	t	f
1404	225	36	INTERMEDIARIO	320	t	f
1405	225	34	INTERMEDIARIO	320	t	f
1406	225	33	BASICO	318	t	f
1407	225	18	INTERMEDIARIO	320	t	f
1408	225	102	BASICO	318	t	f
1409	225	120	BASICO	318	t	f
1410	225	119	INTERMEDIARIO	320	t	f
1411	225	69	INTERMEDIARIO	320	t	f
1412	225	65	INTERMEDIARIO	320	t	f
1413	225	63	INTERMEDIARIO	320	t	f
1414	70	60	INTERMEDIARIO	320	t	f
1415	70	59	INTERMEDIARIO	320	t	f
1416	70	38	BASICO	318	t	f
1417	70	19	INTERMEDIARIO	320	t	f
1418	70	35	BASICO	318	t	f
1419	70	102	BASICO	318	t	f
1420	70	86	BASICO	318	t	f
1421	70	119	BASICO	318	t	f
1422	70	115	BASICO	318	t	f
1423	140	21	INTERMEDIARIO	320	t	f
1424	140	14	INTERMEDIARIO	320	t	f
1425	142	21	BASICO	318	t	f
1426	142	58	BASICO	318	t	f
1427	142	50	BASICO	318	t	f
1428	120	59	BASICO	318	t	f
1429	120	53	BASICO	318	t	f
1430	2	99	AVANCADO	321	t	f
1431	16	70	AVANCADO	321	t	f
1432	16	71	INTERMEDIARIO	320	t	f
1433	16	75	AVANCADO	321	t	f
1434	16	78	INTERMEDIARIO	320	t	f
1435	16	80	BASICO	318	t	f
1436	16	114	AVANCADO	321	t	f
1437	16	119	AVANCADO	321	t	f
1438	16	120	AVANCADO	321	t	f
1439	16	127	INTERMEDIARIO	320	t	f
1440	19	9	BASICO	318	t	f
1441	53	20	AVANCADO	321	t	f
1442	70	16	BASICO	318	t	f
1443	70	18	INTERMEDIARIO	320	t	f
1444	70	20	BASICO	318	t	f
1445	70	26	BASICO	318	t	f
1446	70	41	INTERMEDIARIO	320	t	f
1447	70	53	BASICO	318	t	f
1448	70	65	BASICO	318	t	f
1449	96	2	INTERMEDIARIO	320	t	f
1450	96	12	AVANCADO	321	t	f
1451	96	99	INTERMEDIARIO	320	t	f
1452	101	99	BASICO	318	t	f
1453	114	20	INTERMEDIARIO	320	t	f
1454	114	80	BASICO	318	t	f
1455	128	64	INTERMEDIARIO	320	t	f
1456	129	16	BASICO	318	t	f
1457	129	71	BASICO	318	t	f
1458	129	75	INTERMEDIARIO	320	t	f
1459	129	80	BASICO	318	t	f
1460	129	114	INTERMEDIARIO	320	t	f
1461	142	55	BASICO	318	t	f
1462	142	56	BASICO	318	t	f
1463	148	35	BASICO	318	t	f
1464	148	41	BASICO	318	t	f
1465	148	65	BASICO	318	t	f
1466	155	65	BASICO	318	t	f
1467	155	66	BASICO	318	t	f
1468	155	75	BASICO	318	t	f
1469	163	80	BASICO	318	t	f
1470	163	117	AVANCADO	321	t	f
1471	191	66	AVANCADO	321	t	f
1472	202	99	BASICO	318	t	f
1473	203	30	BASICO	318	t	f
1474	203	58	BASICO	318	t	f
1475	203	75	BASICO	318	t	f
1476	225	80	BASICO	318	t	f
1477	248	16	INTERMEDIARIO	320	t	f
1478	248	20	AVANCADO	321	t	f
1479	248	80	BASICO	318	t	f
1480	251	16	BASICO	318	t	f
1481	251	20	INTERMEDIARIO	320	t	f
1482	251	80	BASICO	318	t	f
1483	251	99	BASICO	318	t	f
1484	253	99	BASICO	318	t	f
1485	259	16	INTERMEDIARIO	320	t	f
1486	259	53	AVANCADO	321	t	f
1487	259	59	AVANCADO	321	t	f
1488	263	26	AVANCADO	321	t	f
1489	263	99	INTERMEDIARIO	320	t	f
1490	265	8	AVANCADO	321	t	f
1491	265	16	AVANCADO	321	t	f
1492	265	20	AVANCADO	321	t	f
1493	265	62	AVANCADO	321	t	f
1494	266	26	BASICO	318	t	f
1495	268	38	BASICO	318	t	f
1496	268	88	BASICO	318	t	f
1497	269	59	BASICO	318	t	f
1498	270	99	BASICO	318	t	f
1499	271	2	AVANCADO	321	t	f
1500	271	12	AVANCADO	321	t	f
1501	271	39	AVANCADO	321	t	f
1502	271	51	BASICO	318	t	f
1503	271	99	INTERMEDIARIO	320	t	f
1504	271	114	INTERMEDIARIO	320	t	f
1505	284	50	INTERMEDIARIO	320	t	f
1506	286	52	AVANCADO	321	t	f
1507	287	21	AVANCADO	321	t	f
1508	287	41	AVANCADO	321	t	f
1509	287	43	INTERMEDIARIO	320	t	f
1510	287	55	INTERMEDIARIO	320	t	f
1511	287	61	INTERMEDIARIO	320	t	f
1512	287	65	AVANCADO	321	t	f
1513	287	72	AVANCADO	321	t	f
1514	287	114	INTERMEDIARIO	320	t	f
1515	287	119	INTERMEDIARIO	320	t	f
1516	68	36	BASICO	318	t	f
1517	68	41	BASICO	318	t	f
1518	68	52	AVANCADO	321	t	f
1519	68	58	BASICO	318	t	f
1520	68	107	INTERMEDIARIO	320	t	f
1521	68	100	BASICO	318	t	f
1522	68	94	BASICO	318	t	f
1523	68	96	INTERMEDIARIO	320	t	f
1524	68	16	BASICO	318	t	f
1525	68	98	INTERMEDIARIO	320	t	f
1526	94	98	AVANCADO	321	t	f
1527	128	101	INTERMEDIARIO	320	t	f
1528	128	102	INTERMEDIARIO	320	t	f
1529	128	50	BASICO	318	t	f
1530	128	51	BASICO	318	t	f
1531	128	52	BASICO	318	t	f
1532	128	29	INTERMEDIARIO	320	t	f
1533	128	34	INTERMEDIARIO	320	t	f
1534	128	36	INTERMEDIARIO	320	t	f
1535	128	15	INTERMEDIARIO	320	t	f
1536	128	16	INTERMEDIARIO	320	t	f
1537	128	19	INTERMEDIARIO	320	t	f
1538	128	20	BASICO	318	t	f
1539	128	21	BASICO	318	t	f
1540	128	24	BASICO	318	t	f
1541	128	25	BASICO	318	t	f
1542	128	55	INTERMEDIARIO	320	t	f
1543	128	56	INTERMEDIARIO	320	t	f
1544	128	58	INTERMEDIARIO	320	t	f
1545	128	59	INTERMEDIARIO	320	t	f
1546	128	61	BASICO	318	t	f
1547	128	84	AVANCADO	321	t	f
1548	128	88	INTERMEDIARIO	320	t	f
1549	128	89	BASICO	318	t	f
1550	128	91	BASICO	318	t	f
1551	128	92	BASICO	318	t	f
1552	128	130	INTERMEDIARIO	320	t	f
1553	128	113	INTERMEDIARIO	320	t	f
1554	128	114	INTERMEDIARIO	320	t	f
1555	128	115	INTERMEDIARIO	320	t	f
1556	128	117	INTERMEDIARIO	320	t	f
1557	128	118	INTERMEDIARIO	320	t	f
1558	128	119	INTERMEDIARIO	320	t	f
1559	128	120	INTERMEDIARIO	320	t	f
1560	128	129	INTERMEDIARIO	320	t	f
1561	128	8	INTERMEDIARIO	320	t	f
1562	128	63	INTERMEDIARIO	320	t	f
1563	128	65	INTERMEDIARIO	320	t	f
1564	128	66	INTERMEDIARIO	320	t	f
1565	128	68	BASICO	318	t	f
1566	128	71	BASICO	318	t	f
1567	128	72	INTERMEDIARIO	320	t	f
1568	128	75	BASICO	318	t	f
1569	128	110	BASICO	318	t	f
1570	302	101	BASICO	318	t	f
1571	302	102	INTERMEDIARIO	320	t	f
1572	302	106	AVANCADO	321	t	f
1573	302	49	AVANCADO	321	t	f
1574	302	50	AVANCADO	321	t	f
1575	302	52	AVANCADO	321	t	f
1576	302	29	AVANCADO	321	t	f
1577	302	30	INTERMEDIARIO	320	t	f
1578	302	34	AVANCADO	321	t	f
1579	302	35	AVANCADO	321	t	f
1580	302	36	AVANCADO	321	t	f
1581	302	37	AVANCADO	321	t	f
1582	302	38	INTERMEDIARIO	320	t	f
1583	302	40	AVANCADO	321	t	f
1584	302	41	AVANCADO	321	t	f
1585	302	42	INTERMEDIARIO	320	t	f
1586	302	43	AVANCADO	321	t	f
1587	302	13	BASICO	318	t	f
1588	302	14	AVANCADO	321	t	f
1589	302	15	INTERMEDIARIO	320	t	f
1590	302	16	INTERMEDIARIO	320	t	f
1591	302	17	BASICO	318	t	f
1592	302	18	INTERMEDIARIO	320	t	f
1593	302	19	INTERMEDIARIO	320	t	f
1594	302	20	INTERMEDIARIO	320	t	f
1595	302	21	AVANCADO	321	t	f
1596	302	22	BASICO	318	t	f
1597	302	23	BASICO	318	t	f
1598	302	24	BASICO	318	t	f
1599	302	25	BASICO	318	t	f
1600	302	26	INTERMEDIARIO	320	t	f
1601	302	27	BASICO	318	t	f
1602	302	53	INTERMEDIARIO	320	t	f
1603	302	54	INTERMEDIARIO	320	t	f
1604	302	55	AVANCADO	321	t	f
1605	302	56	AVANCADO	321	t	f
1606	302	58	AVANCADO	321	t	f
1607	302	59	AVANCADO	321	t	f
1608	302	60	AVANCADO	321	t	f
1609	302	61	AVANCADO	321	t	f
1610	302	62	AVANCADO	321	t	f
1611	302	86	AVANCADO	321	t	f
1612	302	89	AVANCADO	321	t	f
1613	302	94	BASICO	318	t	f
1614	302	97	AVANCADO	321	t	f
1615	302	113	AVANCADO	321	t	f
1616	302	114	AVANCADO	321	t	f
1617	302	115	AVANCADO	321	t	f
1618	302	116	AVANCADO	321	t	f
1619	302	117	AVANCADO	321	t	f
1620	302	118	AVANCADO	321	t	f
1621	302	119	AVANCADO	321	t	f
1622	302	120	AVANCADO	321	t	f
1623	302	123	AVANCADO	321	t	f
1624	302	124	INTERMEDIARIO	320	t	f
1625	302	129	AVANCADO	321	t	f
1626	302	1	INTERMEDIARIO	320	t	f
1627	302	4	INTERMEDIARIO	320	t	f
1628	302	8	AVANCADO	321	t	f
1629	302	9	AVANCADO	321	t	f
1630	302	63	INTERMEDIARIO	320	t	f
1631	302	65	AVANCADO	321	t	f
1632	302	66	AVANCADO	321	t	f
1633	302	68	INTERMEDIARIO	320	t	f
1634	302	71	AVANCADO	321	t	f
1635	302	72	AVANCADO	321	t	f
1636	302	74	INTERMEDIARIO	320	t	f
1637	302	75	INTERMEDIARIO	320	t	f
1638	302	108	AVANCADO	321	t	f
1639	302	109	AVANCADO	321	t	f
1640	302	110	AVANCADO	321	t	f
1641	302	111	AVANCADO	321	t	f
1642	242	98	INTERMEDIARIO	320	t	f
1643	242	102	INTERMEDIARIO	320	t	f
1644	242	103	INTERMEDIARIO	320	t	f
1645	242	104	BASICO	318	t	f
1646	242	106	INTERMEDIARIO	320	t	f
1647	242	50	BASICO	318	t	f
1648	242	51	BASICO	318	t	f
1649	242	29	INTERMEDIARIO	320	t	f
1650	242	30	BASICO	318	t	f
1651	242	34	INTERMEDIARIO	320	t	f
1652	242	36	INTERMEDIARIO	320	t	f
1653	242	41	INTERMEDIARIO	320	t	f
1654	242	44	BASICO	318	t	f
1655	242	19	BASICO	318	t	f
1656	242	21	BASICO	318	t	f
1657	242	55	BASICO	318	t	f
1658	242	56	INTERMEDIARIO	320	t	f
1659	242	58	BASICO	318	t	f
1660	242	59	BASICO	318	t	f
1661	242	83	AVANCADO	321	t	f
1662	242	84	AVANCADO	321	t	f
1663	242	85	BASICO	318	t	f
1664	242	86	AVANCADO	321	t	f
1665	242	87	INTERMEDIARIO	320	t	f
1666	242	88	AVANCADO	321	t	f
1667	242	89	AVANCADO	321	t	f
1668	242	90	BASICO	318	t	f
1669	242	91	AVANCADO	321	t	f
1670	242	92	AVANCADO	321	t	f
1671	242	93	INTERMEDIARIO	320	t	f
1672	242	94	AVANCADO	321	t	f
1673	242	96	INTERMEDIARIO	320	t	f
1674	242	97	INTERMEDIARIO	320	t	f
1675	242	130	AVANCADO	321	t	f
1676	242	114	INTERMEDIARIO	320	t	f
1677	242	115	AVANCADO	321	t	f
1678	242	117	INTERMEDIARIO	320	t	f
1679	242	118	INTERMEDIARIO	320	t	f
1680	242	119	AVANCADO	321	t	f
1681	242	120	INTERMEDIARIO	320	t	f
1682	242	122	BASICO	318	t	f
1683	242	125	INTERMEDIARIO	320	t	f
1684	242	127	BASICO	318	t	f
1685	242	129	INTERMEDIARIO	320	t	f
1686	242	63	BASICO	318	t	f
1687	242	64	BASICO	318	t	f
1688	242	65	INTERMEDIARIO	320	t	f
1689	242	72	AVANCADO	321	t	f
1690	242	78	INTERMEDIARIO	320	t	f
1691	242	82	INTERMEDIARIO	320	t	f
1692	242	112	BASICO	318	t	f
1693	258	98	INTERMEDIARIO	320	t	f
1694	258	99	BASICO	318	t	f
1695	258	100	INTERMEDIARIO	320	t	f
1696	258	101	INTERMEDIARIO	320	t	f
1697	258	102	INTERMEDIARIO	320	t	f
1698	258	103	INTERMEDIARIO	320	t	f
1699	258	104	INTERMEDIARIO	320	t	f
1700	258	105	INTERMEDIARIO	320	t	f
1701	258	106	INTERMEDIARIO	320	t	f
1702	258	48	BASICO	318	t	f
1703	258	50	BASICO	318	t	f
1704	258	51	INTERMEDIARIO	320	t	f
1705	258	55	BASICO	318	t	f
1706	258	56	BASICO	318	t	f
1707	258	58	BASICO	318	t	f
1708	258	59	BASICO	318	t	f
1709	258	113	BASICO	318	t	f
1710	258	114	BASICO	318	t	f
1711	258	115	BASICO	318	t	f
1712	258	117	BASICO	318	t	f
1713	258	1	BASICO	318	t	f
1714	258	2	BASICO	318	t	f
1715	258	64	BASICO	318	t	f
1716	97	98	BASICO	318	t	f
1717	97	99	BASICO	318	t	f
1718	97	102	INTERMEDIARIO	320	t	f
1719	97	104	BASICO	318	t	f
1720	97	105	BASICO	318	t	f
1721	97	106	INTERMEDIARIO	320	t	f
1722	97	48	BASICO	318	t	f
1723	97	49	BASICO	318	t	f
1724	97	50	INTERMEDIARIO	320	t	f
1725	97	51	BASICO	318	t	f
1726	97	52	AVANCADO	321	t	f
1727	97	29	INTERMEDIARIO	320	t	f
1728	97	30	INTERMEDIARIO	320	t	f
1729	97	33	INTERMEDIARIO	320	t	f
1730	97	34	INTERMEDIARIO	320	t	f
1731	97	35	AVANCADO	321	t	f
1732	97	36	AVANCADO	321	t	f
1733	97	37	AVANCADO	321	t	f
1734	97	38	BASICO	318	t	f
1735	97	39	BASICO	318	t	f
1736	97	40	AVANCADO	321	t	f
1737	97	41	AVANCADO	321	t	f
1738	97	42	INTERMEDIARIO	320	t	f
1739	97	43	INTERMEDIARIO	320	t	f
1740	97	44	AVANCADO	321	t	f
1741	97	45	BASICO	318	t	f
1742	97	13	BASICO	318	t	f
1743	97	15	AVANCADO	321	t	f
1744	97	16	BASICO	318	t	f
1745	97	18	BASICO	318	t	f
1746	97	19	AVANCADO	321	t	f
1747	97	20	INTERMEDIARIO	320	t	f
1748	97	53	INTERMEDIARIO	320	t	f
1749	97	54	INTERMEDIARIO	320	t	f
1750	97	55	AVANCADO	321	t	f
1751	97	56	AVANCADO	321	t	f
1752	97	57	INTERMEDIARIO	320	t	f
1753	97	58	AVANCADO	321	t	f
1754	97	59	AVANCADO	321	t	f
1755	97	60	AVANCADO	321	t	f
1756	97	61	AVANCADO	321	t	f
1757	97	84	BASICO	318	t	f
1758	97	86	AVANCADO	321	t	f
1759	97	97	AVANCADO	321	t	f
1760	97	113	INTERMEDIARIO	320	t	f
1761	97	114	INTERMEDIARIO	320	t	f
1762	97	115	AVANCADO	321	t	f
1763	97	116	BASICO	318	t	f
1764	97	117	AVANCADO	321	t	f
1765	97	118	INTERMEDIARIO	320	t	f
1766	97	119	INTERMEDIARIO	320	t	f
1767	97	120	BASICO	318	t	f
1768	97	122	BASICO	318	t	f
1769	97	123	BASICO	318	t	f
1770	97	124	INTERMEDIARIO	320	t	f
1771	97	126	BASICO	318	t	f
1772	97	129	INTERMEDIARIO	320	t	f
1773	97	1	AVANCADO	321	t	f
1774	97	4	AVANCADO	321	t	f
1775	97	7	AVANCADO	321	t	f
1776	97	8	AVANCADO	321	t	f
1777	97	9	AVANCADO	321	t	f
1778	97	12	AVANCADO	321	t	f
1779	97	63	BASICO	318	t	f
1780	97	64	INTERMEDIARIO	320	t	f
1781	97	65	INTERMEDIARIO	320	t	f
1782	97	66	INTERMEDIARIO	320	t	f
1783	97	68	BASICO	318	t	f
1784	97	69	INTERMEDIARIO	320	t	f
1785	97	71	BASICO	318	t	f
1786	97	72	INTERMEDIARIO	320	t	f
1787	97	74	BASICO	318	t	f
1788	97	75	INTERMEDIARIO	320	t	f
1789	97	82	INTERMEDIARIO	320	t	f
1790	97	108	AVANCADO	321	t	f
1791	97	109	AVANCADO	321	t	f
1792	97	111	INTERMEDIARIO	320	t	f
1793	66	102	INTERMEDIARIO	320	t	f
1794	66	103	INTERMEDIARIO	320	t	f
1795	66	104	INTERMEDIARIO	320	t	f
1796	66	105	BASICO	318	t	f
1797	66	106	INTERMEDIARIO	320	t	f
1798	66	107	INTERMEDIARIO	320	t	f
1799	66	50	INTERMEDIARIO	320	t	f
1800	66	51	INTERMEDIARIO	320	t	f
1801	66	28	INTERMEDIARIO	320	t	f
1802	66	29	AVANCADO	321	t	f
1803	66	30	AVANCADO	321	t	f
1804	66	31	INTERMEDIARIO	320	t	f
1805	66	32	INTERMEDIARIO	320	t	f
1806	66	33	AVANCADO	321	t	f
1807	66	34	AVANCADO	321	t	f
1808	66	35	AVANCADO	321	t	f
1809	66	36	AVANCADO	321	t	f
1810	66	37	INTERMEDIARIO	320	t	f
1811	66	38	AVANCADO	321	t	f
1812	66	39	AVANCADO	321	t	f
1813	66	40	AVANCADO	321	t	f
1814	66	41	AVANCADO	321	t	f
1815	66	42	INTERMEDIARIO	320	t	f
1816	66	43	INTERMEDIARIO	320	t	f
1817	66	44	AVANCADO	321	t	f
1818	66	45	AVANCADO	321	t	f
1819	66	46	AVANCADO	321	t	f
1820	66	14	INTERMEDIARIO	320	t	f
1821	66	16	INTERMEDIARIO	320	t	f
1822	66	17	INTERMEDIARIO	320	t	f
1823	66	19	INTERMEDIARIO	320	t	f
1824	66	21	INTERMEDIARIO	320	t	f
1825	66	22	INTERMEDIARIO	320	t	f
1826	66	26	BASICO	318	t	f
1827	66	53	INTERMEDIARIO	320	t	f
1828	66	54	INTERMEDIARIO	320	t	f
1829	66	55	INTERMEDIARIO	320	t	f
1830	66	56	INTERMEDIARIO	320	t	f
1831	66	57	INTERMEDIARIO	320	t	f
1832	66	58	INTERMEDIARIO	320	t	f
1833	66	59	BASICO	318	t	f
1834	66	60	BASICO	318	t	f
1835	66	61	INTERMEDIARIO	320	t	f
1836	66	62	BASICO	318	t	f
1837	66	92	INTERMEDIARIO	320	t	f
1838	66	113	INTERMEDIARIO	320	t	f
1839	66	115	INTERMEDIARIO	320	t	f
1840	66	116	INTERMEDIARIO	320	t	f
1841	66	117	INTERMEDIARIO	320	t	f
1842	66	118	INTERMEDIARIO	320	t	f
1843	66	119	INTERMEDIARIO	320	t	f
1844	66	120	INTERMEDIARIO	320	t	f
1845	66	123	INTERMEDIARIO	320	t	f
1846	66	129	AVANCADO	321	t	f
1847	66	1	INTERMEDIARIO	320	t	f
1848	66	8	INTERMEDIARIO	320	t	f
1849	66	10	INTERMEDIARIO	320	t	f
1850	66	11	INTERMEDIARIO	320	t	f
1851	66	12	INTERMEDIARIO	320	t	f
1852	66	63	INTERMEDIARIO	320	t	f
1853	66	64	INTERMEDIARIO	320	t	f
1854	66	65	INTERMEDIARIO	320	t	f
1855	66	66	INTERMEDIARIO	320	t	f
1856	66	67	INTERMEDIARIO	320	t	f
1857	66	72	INTERMEDIARIO	320	t	f
1858	66	82	INTERMEDIARIO	320	t	f
1859	262	98	INTERMEDIARIO	320	t	f
1860	262	99	BASICO	318	t	f
1861	262	100	BASICO	318	t	f
1862	262	101	BASICO	318	t	f
1863	262	102	BASICO	318	t	f
1864	262	103	BASICO	318	t	f
1865	262	104	BASICO	318	t	f
1866	262	105	BASICO	318	t	f
1867	262	106	AVANCADO	321	t	f
1868	262	107	INTERMEDIARIO	320	t	f
1869	262	47	BASICO	318	t	f
1870	262	48	BASICO	318	t	f
1871	262	49	BASICO	318	t	f
1872	262	50	INTERMEDIARIO	320	t	f
1873	262	51	BASICO	318	t	f
1874	262	52	INTERMEDIARIO	320	t	f
1875	262	28	BASICO	318	t	f
1876	262	29	INTERMEDIARIO	320	t	f
1877	262	30	BASICO	318	t	f
1878	262	31	BASICO	318	t	f
1879	262	32	BASICO	318	t	f
1880	262	33	BASICO	318	t	f
1881	262	34	BASICO	318	t	f
1882	262	35	BASICO	318	t	f
1883	262	36	INTERMEDIARIO	320	t	f
1884	262	37	BASICO	318	t	f
1885	262	38	BASICO	318	t	f
1886	262	39	BASICO	318	t	f
1887	262	40	BASICO	318	t	f
1888	262	41	BASICO	318	t	f
1889	262	42	BASICO	318	t	f
1890	262	43	BASICO	318	t	f
1891	262	44	INTERMEDIARIO	320	t	f
1892	262	45	BASICO	318	t	f
1893	262	46	BASICO	318	t	f
1894	262	13	BASICO	318	t	f
1895	262	14	BASICO	318	t	f
1896	262	15	BASICO	318	t	f
1897	262	16	BASICO	318	t	f
1898	262	17	BASICO	318	t	f
1899	262	18	INTERMEDIARIO	320	t	f
1900	262	19	BASICO	318	t	f
1901	262	20	INTERMEDIARIO	320	t	f
1902	262	21	BASICO	318	t	f
1903	262	22	BASICO	318	t	f
1904	262	23	BASICO	318	t	f
1905	262	24	BASICO	318	t	f
1906	262	25	BASICO	318	t	f
1907	262	26	BASICO	318	t	f
1908	262	27	BASICO	318	t	f
1909	262	54	AVANCADO	321	t	f
1910	262	55	AVANCADO	321	t	f
1911	262	56	AVANCADO	321	t	f
1912	262	57	BASICO	318	t	f
1913	262	58	AVANCADO	321	t	f
1914	262	60	BASICO	318	t	f
1915	262	61	AVANCADO	321	t	f
1916	262	62	BASICO	318	t	f
1917	262	83	BASICO	318	t	f
1918	262	84	BASICO	318	t	f
1919	262	85	BASICO	318	t	f
1920	262	86	BASICO	318	t	f
1921	262	87	BASICO	318	t	f
1922	262	88	BASICO	318	t	f
1923	262	89	BASICO	318	t	f
1924	262	90	BASICO	318	t	f
1925	262	91	BASICO	318	t	f
1926	262	92	BASICO	318	t	f
1927	262	93	BASICO	318	t	f
1928	262	94	BASICO	318	t	f
1929	262	95	BASICO	318	t	f
1930	262	96	BASICO	318	t	f
1931	262	97	BASICO	318	t	f
1932	262	130	BASICO	318	t	f
1933	262	113	BASICO	318	t	f
1934	262	114	BASICO	318	t	f
1935	262	115	INTERMEDIARIO	320	t	f
1936	262	116	BASICO	318	t	f
1937	262	117	INTERMEDIARIO	320	t	f
1938	262	118	BASICO	318	t	f
1939	262	119	INTERMEDIARIO	320	t	f
1940	262	120	BASICO	318	t	f
1941	262	121	BASICO	318	t	f
1942	262	122	BASICO	318	t	f
1943	262	123	BASICO	318	t	f
1944	262	124	BASICO	318	t	f
1945	262	125	BASICO	318	t	f
1946	262	126	BASICO	318	t	f
1947	262	127	BASICO	318	t	f
1948	262	129	BASICO	318	t	f
1949	262	1	BASICO	318	t	f
1950	262	2	BASICO	318	t	f
1951	262	3	BASICO	318	t	f
1952	262	4	BASICO	318	t	f
1953	262	5	BASICO	318	t	f
1954	262	6	BASICO	318	t	f
1955	262	7	INTERMEDIARIO	320	t	f
1956	262	8	INTERMEDIARIO	320	t	f
1957	262	9	AVANCADO	321	t	f
1958	262	10	BASICO	318	t	f
1959	262	11	BASICO	318	t	f
1960	262	12	BASICO	318	t	f
1961	262	63	BASICO	318	t	f
1962	262	64	BASICO	318	t	f
1963	262	65	BASICO	318	t	f
1964	262	66	BASICO	318	t	f
1965	262	67	BASICO	318	t	f
1966	262	68	BASICO	318	t	f
1967	262	69	BASICO	318	t	f
1968	262	70	BASICO	318	t	f
1969	262	71	BASICO	318	t	f
1970	262	72	INTERMEDIARIO	320	t	f
1971	262	73	BASICO	318	t	f
1972	262	74	BASICO	318	t	f
1973	262	75	BASICO	318	t	f
1974	262	76	BASICO	318	t	f
1975	262	77	BASICO	318	t	f
1976	262	78	BASICO	318	t	f
1977	262	79	BASICO	318	t	f
1978	262	81	BASICO	318	t	f
1979	262	82	BASICO	318	t	f
1980	262	108	AVANCADO	321	t	f
1981	262	109	BASICO	318	t	f
1982	262	110	INTERMEDIARIO	320	t	f
1983	262	111	BASICO	318	t	f
1984	262	112	BASICO	318	t	f
1985	84	98	BASICO	318	t	f
1986	84	102	BASICO	318	t	f
1987	84	106	BASICO	318	t	f
1988	84	49	BASICO	318	t	f
1989	84	29	INTERMEDIARIO	320	t	f
1990	84	34	BASICO	318	t	f
1991	84	35	BASICO	318	t	f
1992	84	36	BASICO	318	t	f
1993	84	39	BASICO	318	t	f
1994	84	41	INTERMEDIARIO	320	t	f
1995	84	42	BASICO	318	t	f
1996	84	43	BASICO	318	t	f
1997	84	44	BASICO	318	t	f
1998	84	21	BASICO	318	t	f
1999	84	23	INTERMEDIARIO	320	t	f
2000	84	55	BASICO	318	t	f
2001	84	56	BASICO	318	t	f
2002	84	58	BASICO	318	t	f
2003	84	61	BASICO	318	t	f
2004	84	86	BASICO	318	t	f
2005	84	87	BASICO	318	t	f
2006	84	91	BASICO	318	t	f
2007	84	114	BASICO	318	t	f
2008	84	115	INTERMEDIARIO	320	t	f
2009	84	116	BASICO	318	t	f
2010	84	117	INTERMEDIARIO	320	t	f
2011	84	119	INTERMEDIARIO	320	t	f
2012	84	122	BASICO	318	t	f
2013	84	123	BASICO	318	t	f
2014	84	1	INTERMEDIARIO	320	t	f
2015	84	4	INTERMEDIARIO	320	t	f
2016	84	8	BASICO	318	t	f
2017	84	9	INTERMEDIARIO	320	t	f
2018	84	63	BASICO	318	t	f
2019	84	65	INTERMEDIARIO	320	t	f
2020	84	66	INTERMEDIARIO	320	t	f
2021	84	71	INTERMEDIARIO	320	t	f
2022	84	72	BASICO	318	t	f
2023	84	108	INTERMEDIARIO	320	t	f
2024	84	109	INTERMEDIARIO	320	t	f
2025	84	110	BASICO	318	t	f
2026	84	111	BASICO	318	t	f
2027	278	98	BASICO	318	t	f
2028	278	99	BASICO	318	t	f
2029	278	100	BASICO	318	t	f
2030	278	101	BASICO	318	t	f
2031	278	102	INTERMEDIARIO	320	t	f
2032	278	103	BASICO	318	t	f
2033	278	104	BASICO	318	t	f
2034	278	105	BASICO	318	t	f
2035	278	106	INTERMEDIARIO	320	t	f
2036	278	107	INTERMEDIARIO	320	t	f
2037	278	47	BASICO	318	t	f
2038	278	48	BASICO	318	t	f
2039	278	49	BASICO	318	t	f
2040	278	50	BASICO	318	t	f
2041	278	51	BASICO	318	t	f
2042	278	52	INTERMEDIARIO	320	t	f
2043	278	28	BASICO	318	t	f
2044	278	29	AVANCADO	321	t	f
2045	278	30	INTERMEDIARIO	320	t	f
2046	278	31	BASICO	318	t	f
2047	278	32	BASICO	318	t	f
2048	278	33	BASICO	318	t	f
2049	278	34	BASICO	318	t	f
2050	278	35	BASICO	318	t	f
2051	278	36	AVANCADO	321	t	f
2052	278	37	AVANCADO	321	t	f
2053	278	38	INTERMEDIARIO	320	t	f
2054	278	39	INTERMEDIARIO	320	t	f
2055	278	40	AVANCADO	321	t	f
2056	278	41	AVANCADO	321	t	f
2057	278	42	BASICO	318	t	f
2058	278	43	BASICO	318	t	f
2059	278	44	AVANCADO	321	t	f
2060	278	45	BASICO	318	t	f
2061	278	46	BASICO	318	t	f
2062	278	13	INTERMEDIARIO	320	t	f
2063	278	14	BASICO	318	t	f
2064	278	15	BASICO	318	t	f
2065	278	17	BASICO	318	t	f
2066	278	18	INTERMEDIARIO	320	t	f
2067	278	19	INTERMEDIARIO	320	t	f
2068	278	21	BASICO	318	t	f
2069	278	22	BASICO	318	t	f
2070	278	23	BASICO	318	t	f
2071	278	24	BASICO	318	t	f
2072	278	25	BASICO	318	t	f
2073	278	26	AVANCADO	321	t	f
2074	278	27	BASICO	318	t	f
2075	278	53	BASICO	318	t	f
2076	278	54	BASICO	318	t	f
2077	278	55	INTERMEDIARIO	320	t	f
2078	278	56	INTERMEDIARIO	320	t	f
2079	278	57	BASICO	318	t	f
2080	278	58	AVANCADO	321	t	f
2081	278	60	AVANCADO	321	t	f
2082	278	61	AVANCADO	321	t	f
2083	278	62	BASICO	318	t	f
2084	278	83	BASICO	318	t	f
2085	278	84	BASICO	318	t	f
2086	278	85	BASICO	318	t	f
2087	278	86	INTERMEDIARIO	320	t	f
2088	278	87	BASICO	318	t	f
2089	278	88	BASICO	318	t	f
2090	278	89	BASICO	318	t	f
2091	278	90	BASICO	318	t	f
2092	278	91	BASICO	318	t	f
2093	278	92	BASICO	318	t	f
2094	278	93	BASICO	318	t	f
2095	278	94	INTERMEDIARIO	320	t	f
2096	278	95	BASICO	318	t	f
2097	278	96	BASICO	318	t	f
2098	278	97	BASICO	318	t	f
2099	278	130	BASICO	318	t	f
2100	278	113	INTERMEDIARIO	320	t	f
2101	278	114	INTERMEDIARIO	320	t	f
2102	278	115	AVANCADO	321	t	f
2103	278	116	AVANCADO	321	t	f
2104	278	117	AVANCADO	321	t	f
2105	278	118	AVANCADO	321	t	f
2106	278	119	INTERMEDIARIO	320	t	f
2107	278	120	INTERMEDIARIO	320	t	f
2108	278	121	BASICO	318	t	f
2109	278	122	BASICO	318	t	f
2110	278	123	INTERMEDIARIO	320	t	f
2111	278	124	BASICO	318	t	f
2112	278	125	INTERMEDIARIO	320	t	f
2113	278	126	BASICO	318	t	f
2114	278	127	BASICO	318	t	f
2115	278	129	AVANCADO	321	t	f
2116	278	1	BASICO	318	t	f
2117	278	2	BASICO	318	t	f
2118	278	3	BASICO	318	t	f
2119	278	4	INTERMEDIARIO	320	t	f
2120	278	5	BASICO	318	t	f
2121	278	6	BASICO	318	t	f
2122	278	7	INTERMEDIARIO	320	t	f
2123	278	8	INTERMEDIARIO	320	t	f
2124	278	9	INTERMEDIARIO	320	t	f
2125	278	10	BASICO	318	t	f
2126	278	11	BASICO	318	t	f
2127	278	12	INTERMEDIARIO	320	t	f
2128	278	63	INTERMEDIARIO	320	t	f
2129	278	64	INTERMEDIARIO	320	t	f
2130	278	65	INTERMEDIARIO	320	t	f
2131	278	66	INTERMEDIARIO	320	t	f
2132	278	67	BASICO	318	t	f
2133	278	68	BASICO	318	t	f
2134	278	69	AVANCADO	321	t	f
2135	278	70	BASICO	318	t	f
2136	278	71	INTERMEDIARIO	320	t	f
2137	278	72	INTERMEDIARIO	320	t	f
2138	278	73	BASICO	318	t	f
2139	278	74	BASICO	318	t	f
2140	278	75	BASICO	318	t	f
2141	278	76	BASICO	318	t	f
2142	278	77	BASICO	318	t	f
2143	278	78	INTERMEDIARIO	320	t	f
2144	278	79	BASICO	318	t	f
2145	278	81	BASICO	318	t	f
2146	278	82	BASICO	318	t	f
2147	278	108	INTERMEDIARIO	320	t	f
2148	278	109	INTERMEDIARIO	320	t	f
2149	278	110	BASICO	318	t	f
2150	278	111	AVANCADO	321	t	f
2151	278	112	BASICO	318	t	f
2152	235	98	AVANCADO	321	t	f
2153	235	99	AVANCADO	321	t	f
2154	235	100	INTERMEDIARIO	320	t	f
2155	235	101	BASICO	318	t	f
2156	235	102	INTERMEDIARIO	320	t	f
2157	235	103	INTERMEDIARIO	320	t	f
2158	235	104	INTERMEDIARIO	320	t	f
2159	235	105	INTERMEDIARIO	320	t	f
2160	235	106	INTERMEDIARIO	320	t	f
2161	235	107	AVANCADO	321	t	f
2162	235	47	INTERMEDIARIO	320	t	f
2163	235	29	INTERMEDIARIO	320	t	f
2164	235	33	INTERMEDIARIO	320	t	f
2165	235	34	INTERMEDIARIO	320	t	f
2166	235	35	INTERMEDIARIO	320	t	f
2167	235	36	INTERMEDIARIO	320	t	f
2168	235	38	INTERMEDIARIO	320	t	f
2169	235	39	INTERMEDIARIO	320	t	f
2170	235	40	INTERMEDIARIO	320	t	f
2171	235	41	INTERMEDIARIO	320	t	f
2172	235	43	INTERMEDIARIO	320	t	f
2173	235	46	INTERMEDIARIO	320	t	f
2174	235	21	BASICO	318	t	f
2175	235	6	BASICO	318	t	f
2176	235	12	BASICO	318	t	f
2177	79	98	BASICO	318	t	f
2178	79	99	INTERMEDIARIO	320	t	f
2179	79	100	INTERMEDIARIO	320	t	f
2180	79	101	BASICO	318	t	f
2181	79	102	BASICO	318	t	f
2182	79	103	AVANCADO	321	t	f
2183	79	104	BASICO	318	t	f
2184	79	105	BASICO	318	t	f
2185	79	106	INTERMEDIARIO	320	t	f
2186	79	107	INTERMEDIARIO	320	t	f
2187	79	47	BASICO	318	t	f
2188	79	48	INTERMEDIARIO	320	t	f
2189	79	49	BASICO	318	t	f
2190	79	50	BASICO	318	t	f
2191	79	51	BASICO	318	t	f
2192	79	52	BASICO	318	t	f
2193	79	28	AVANCADO	321	t	f
2194	79	29	INTERMEDIARIO	320	t	f
2195	79	30	BASICO	318	t	f
2196	79	31	BASICO	318	t	f
2197	79	32	BASICO	318	t	f
2198	79	33	BASICO	318	t	f
2199	79	34	BASICO	318	t	f
2200	79	35	BASICO	318	t	f
2201	79	36	INTERMEDIARIO	320	t	f
2202	79	37	BASICO	318	t	f
2203	79	38	INTERMEDIARIO	320	t	f
2204	79	39	AVANCADO	321	t	f
2205	79	40	BASICO	318	t	f
2206	79	41	INTERMEDIARIO	320	t	f
2207	79	42	BASICO	318	t	f
2208	79	43	BASICO	318	t	f
2209	79	44	BASICO	318	t	f
2210	79	45	BASICO	318	t	f
2211	79	46	BASICO	318	t	f
2212	79	13	BASICO	318	t	f
2213	79	14	BASICO	318	t	f
2214	79	15	BASICO	318	t	f
2215	79	16	INTERMEDIARIO	320	t	f
2216	79	17	BASICO	318	t	f
2217	79	18	BASICO	318	t	f
2218	79	19	BASICO	318	t	f
2219	79	20	BASICO	318	t	f
2220	79	21	BASICO	318	t	f
2221	79	22	BASICO	318	t	f
2222	79	23	BASICO	318	t	f
2223	79	24	BASICO	318	t	f
2224	79	25	BASICO	318	t	f
2225	79	26	BASICO	318	t	f
2226	79	27	BASICO	318	t	f
2227	79	53	BASICO	318	t	f
2228	79	54	BASICO	318	t	f
2229	79	55	BASICO	318	t	f
2230	79	56	BASICO	318	t	f
2231	79	57	BASICO	318	t	f
2232	79	58	BASICO	318	t	f
2233	79	59	BASICO	318	t	f
2234	79	60	BASICO	318	t	f
2235	79	61	BASICO	318	t	f
2236	79	62	BASICO	318	t	f
2237	79	83	BASICO	318	t	f
2238	79	84	BASICO	318	t	f
2239	79	85	BASICO	318	t	f
2240	79	86	BASICO	318	t	f
2241	79	87	BASICO	318	t	f
2242	79	88	BASICO	318	t	f
2243	79	89	BASICO	318	t	f
2244	79	90	BASICO	318	t	f
2245	79	91	BASICO	318	t	f
2246	79	92	BASICO	318	t	f
2247	79	93	BASICO	318	t	f
2248	79	94	BASICO	318	t	f
2249	79	95	BASICO	318	t	f
2250	79	96	BASICO	318	t	f
2251	79	97	BASICO	318	t	f
2252	79	130	BASICO	318	t	f
2253	79	113	BASICO	318	t	f
2254	79	114	BASICO	318	t	f
2255	79	115	INTERMEDIARIO	320	t	f
2256	79	116	BASICO	318	t	f
2257	79	117	INTERMEDIARIO	320	t	f
2258	79	118	BASICO	318	t	f
2259	79	119	INTERMEDIARIO	320	t	f
2260	79	120	BASICO	318	t	f
2261	79	121	BASICO	318	t	f
2262	79	122	BASICO	318	t	f
2263	79	123	BASICO	318	t	f
2264	79	124	BASICO	318	t	f
2265	79	125	BASICO	318	t	f
2266	79	126	BASICO	318	t	f
2267	79	127	BASICO	318	t	f
2268	79	129	BASICO	318	t	f
2269	79	1	BASICO	318	t	f
2270	79	2	BASICO	318	t	f
2271	79	3	BASICO	318	t	f
2272	79	4	BASICO	318	t	f
2273	79	5	BASICO	318	t	f
2274	79	6	BASICO	318	t	f
2275	79	7	BASICO	318	t	f
2276	79	8	BASICO	318	t	f
2277	79	9	BASICO	318	t	f
2278	79	10	BASICO	318	t	f
2279	79	11	BASICO	318	t	f
2280	79	12	BASICO	318	t	f
2281	79	63	BASICO	318	t	f
2282	79	64	BASICO	318	t	f
2283	79	65	BASICO	318	t	f
2284	79	66	BASICO	318	t	f
2285	79	67	BASICO	318	t	f
2286	79	68	BASICO	318	t	f
2287	79	69	BASICO	318	t	f
2288	79	70	BASICO	318	t	f
2289	79	71	BASICO	318	t	f
2290	79	72	INTERMEDIARIO	320	t	f
2291	79	73	BASICO	318	t	f
2292	79	74	BASICO	318	t	f
2293	79	75	BASICO	318	t	f
2294	79	76	BASICO	318	t	f
2295	79	77	BASICO	318	t	f
2296	79	78	BASICO	318	t	f
2297	79	79	BASICO	318	t	f
2298	79	81	BASICO	318	t	f
2299	79	82	BASICO	318	t	f
2300	79	108	BASICO	318	t	f
2301	79	109	BASICO	318	t	f
2302	79	110	BASICO	318	t	f
2303	79	111	BASICO	318	t	f
2304	79	112	BASICO	318	t	f
2305	251	98	BASICO	318	t	f
2306	251	100	BASICO	318	t	f
2307	251	101	INTERMEDIARIO	320	t	f
2308	251	103	BASICO	318	t	f
2309	251	104	BASICO	318	t	f
2310	251	105	BASICO	318	t	f
2311	251	107	INTERMEDIARIO	320	t	f
2312	251	47	BASICO	318	t	f
2313	251	48	INTERMEDIARIO	320	t	f
2314	251	49	BASICO	318	t	f
2315	251	51	BASICO	318	t	f
2316	251	52	BASICO	318	t	f
2317	251	28	BASICO	318	t	f
2318	251	29	BASICO	318	t	f
2319	251	30	BASICO	318	t	f
2320	251	31	BASICO	318	t	f
2321	251	32	BASICO	318	t	f
2322	251	34	BASICO	318	t	f
2323	251	35	BASICO	318	t	f
2324	251	37	INTERMEDIARIO	320	t	f
2325	251	39	BASICO	318	t	f
2326	251	40	INTERMEDIARIO	320	t	f
2327	251	42	BASICO	318	t	f
2328	251	44	BASICO	318	t	f
2329	251	45	BASICO	318	t	f
2330	251	46	BASICO	318	t	f
2331	251	13	BASICO	318	t	f
2332	251	14	BASICO	318	t	f
2333	251	15	BASICO	318	t	f
2334	251	17	BASICO	318	t	f
2335	251	21	BASICO	318	t	f
2336	251	22	BASICO	318	t	f
2337	251	23	BASICO	318	t	f
2338	251	24	BASICO	318	t	f
2339	251	25	BASICO	318	t	f
2340	251	27	BASICO	318	t	f
2341	251	53	BASICO	318	t	f
2342	251	54	BASICO	318	t	f
2343	251	55	AVANCADO	321	t	f
2344	251	56	AVANCADO	321	t	f
2345	251	57	INTERMEDIARIO	320	t	f
2346	251	58	AVANCADO	321	t	f
2347	251	60	BASICO	318	t	f
2348	251	83	BASICO	318	t	f
2349	251	84	BASICO	318	t	f
2350	251	85	BASICO	318	t	f
2351	251	86	BASICO	318	t	f
2352	251	87	BASICO	318	t	f
2353	251	88	BASICO	318	t	f
2354	251	89	BASICO	318	t	f
2355	251	90	BASICO	318	t	f
2356	251	91	BASICO	318	t	f
2357	251	92	BASICO	318	t	f
2358	251	93	BASICO	318	t	f
2359	251	94	BASICO	318	t	f
2360	251	95	BASICO	318	t	f
2361	251	96	BASICO	318	t	f
2362	251	97	BASICO	318	t	f
2363	251	130	BASICO	318	t	f
2364	251	113	INTERMEDIARIO	320	t	f
2365	251	114	INTERMEDIARIO	320	t	f
2366	251	115	INTERMEDIARIO	320	t	f
2367	251	116	INTERMEDIARIO	320	t	f
2368	251	118	INTERMEDIARIO	320	t	f
2369	251	121	BASICO	318	t	f
2370	251	122	INTERMEDIARIO	320	t	f
2371	251	123	INTERMEDIARIO	320	t	f
2372	251	124	INTERMEDIARIO	320	t	f
2373	251	125	BASICO	318	t	f
2374	251	126	BASICO	318	t	f
2375	251	127	BASICO	318	t	f
2376	251	129	INTERMEDIARIO	320	t	f
2377	251	1	INTERMEDIARIO	320	t	f
2378	251	2	INTERMEDIARIO	320	t	f
2379	251	3	BASICO	318	t	f
2380	251	4	INTERMEDIARIO	320	t	f
2381	251	5	BASICO	318	t	f
2382	251	6	BASICO	318	t	f
2383	251	7	BASICO	318	t	f
2384	251	8	INTERMEDIARIO	320	t	f
2385	251	9	INTERMEDIARIO	320	t	f
2386	251	10	INTERMEDIARIO	320	t	f
2387	251	12	INTERMEDIARIO	320	t	f
2388	251	63	BASICO	318	t	f
2389	251	64	BASICO	318	t	f
2390	251	66	BASICO	318	t	f
2391	251	67	BASICO	318	t	f
2392	251	68	BASICO	318	t	f
2393	251	69	BASICO	318	t	f
2394	251	70	BASICO	318	t	f
2395	251	71	BASICO	318	t	f
2396	251	72	BASICO	318	t	f
2397	251	73	BASICO	318	t	f
2398	251	74	BASICO	318	t	f
2399	251	75	BASICO	318	t	f
2400	251	76	BASICO	318	t	f
2401	251	77	BASICO	318	t	f
2402	251	78	BASICO	318	t	f
2403	251	79	BASICO	318	t	f
2404	251	81	BASICO	318	t	f
2405	251	82	BASICO	318	t	f
2406	251	108	INTERMEDIARIO	320	t	f
2407	251	109	INTERMEDIARIO	320	t	f
2408	251	111	BASICO	318	t	f
2409	251	112	BASICO	318	t	f
2410	163	98	AVANCADO	321	t	f
2411	163	99	BASICO	318	t	f
2412	163	100	BASICO	318	t	f
2413	163	101	AVANCADO	321	t	f
2414	163	104	AVANCADO	321	t	f
2415	163	49	BASICO	318	t	f
2416	163	50	INTERMEDIARIO	320	t	f
2417	163	51	INTERMEDIARIO	320	t	f
2418	163	52	AVANCADO	321	t	f
2419	163	29	INTERMEDIARIO	320	t	f
2420	163	33	INTERMEDIARIO	320	t	f
2421	163	35	INTERMEDIARIO	320	t	f
2422	163	36	INTERMEDIARIO	320	t	f
2423	163	37	INTERMEDIARIO	320	t	f
2424	163	40	INTERMEDIARIO	320	t	f
2425	163	42	BASICO	318	t	f
2426	163	43	INTERMEDIARIO	320	t	f
2427	163	44	BASICO	318	t	f
2428	163	15	INTERMEDIARIO	320	t	f
2429	163	20	INTERMEDIARIO	320	t	f
2430	163	27	INTERMEDIARIO	320	t	f
2431	163	54	INTERMEDIARIO	320	t	f
2432	163	55	AVANCADO	321	t	f
2433	163	56	AVANCADO	321	t	f
2434	163	57	INTERMEDIARIO	320	t	f
2435	163	58	AVANCADO	321	t	f
2436	163	86	AVANCADO	321	t	f
2437	163	87	AVANCADO	321	t	f
2438	163	88	AVANCADO	321	t	f
2439	163	90	INTERMEDIARIO	320	t	f
2440	163	91	AVANCADO	321	t	f
2441	163	92	AVANCADO	321	t	f
2442	163	93	INTERMEDIARIO	320	t	f
2443	163	94	INTERMEDIARIO	320	t	f
2444	163	130	AVANCADO	321	t	f
2445	163	114	AVANCADO	321	t	f
2446	163	115	AVANCADO	321	t	f
2447	163	122	INTERMEDIARIO	320	t	f
2448	163	123	INTERMEDIARIO	320	t	f
2449	163	124	INTERMEDIARIO	320	t	f
2450	163	126	INTERMEDIARIO	320	t	f
2451	163	129	INTERMEDIARIO	320	t	f
2452	163	1	AVANCADO	321	t	f
2453	163	9	AVANCADO	321	t	f
2454	163	63	BASICO	318	t	f
2455	163	64	BASICO	318	t	f
2456	163	66	INTERMEDIARIO	320	t	f
2457	163	67	INTERMEDIARIO	320	t	f
2458	163	71	BASICO	318	t	f
2459	163	72	BASICO	318	t	f
2460	163	73	BASICO	318	t	f
2461	163	75	BASICO	318	t	f
2462	163	108	AVANCADO	321	t	f
2463	163	109	AVANCADO	321	t	f
2464	163	110	AVANCADO	321	t	f
2465	163	111	AVANCADO	321	t	f
2466	263	98	AVANCADO	321	t	f
2467	263	100	INTERMEDIARIO	320	t	f
2468	263	101	AVANCADO	321	t	f
2469	263	102	AVANCADO	321	t	f
2470	263	103	INTERMEDIARIO	320	t	f
2471	263	104	INTERMEDIARIO	320	t	f
2472	263	105	AVANCADO	321	t	f
2473	263	106	AVANCADO	321	t	f
2474	263	107	AVANCADO	321	t	f
2475	263	47	AVANCADO	321	t	f
2476	263	48	INTERMEDIARIO	320	t	f
2477	263	49	AVANCADO	321	t	f
2478	263	51	AVANCADO	321	t	f
2479	263	52	AVANCADO	321	t	f
2480	263	28	AVANCADO	321	t	f
2481	263	29	AVANCADO	321	t	f
2482	263	30	AVANCADO	321	t	f
2483	263	31	AVANCADO	321	t	f
2484	263	32	BASICO	318	t	f
2485	263	33	AVANCADO	321	t	f
2486	263	35	AVANCADO	321	t	f
2487	263	36	AVANCADO	321	t	f
2488	263	37	AVANCADO	321	t	f
2489	263	39	AVANCADO	321	t	f
2490	263	40	AVANCADO	321	t	f
2491	263	42	AVANCADO	321	t	f
2492	263	43	AVANCADO	321	t	f
2493	263	44	AVANCADO	321	t	f
2494	263	45	INTERMEDIARIO	320	t	f
2495	263	46	AVANCADO	321	t	f
2496	263	13	INTERMEDIARIO	320	t	f
2497	263	14	AVANCADO	321	t	f
2498	263	15	AVANCADO	321	t	f
2499	263	16	AVANCADO	321	t	f
2500	263	17	INTERMEDIARIO	320	t	f
2501	263	18	INTERMEDIARIO	320	t	f
2502	263	20	AVANCADO	321	t	f
2503	263	21	AVANCADO	321	t	f
2504	263	22	INTERMEDIARIO	320	t	f
2505	263	24	INTERMEDIARIO	320	t	f
2506	263	25	INTERMEDIARIO	320	t	f
2507	263	27	INTERMEDIARIO	320	t	f
2508	263	54	AVANCADO	321	t	f
2509	263	55	AVANCADO	321	t	f
2510	263	56	AVANCADO	321	t	f
2511	263	57	INTERMEDIARIO	320	t	f
2512	263	58	AVANCADO	321	t	f
2513	263	60	INTERMEDIARIO	320	t	f
2514	263	61	AVANCADO	321	t	f
2515	263	83	INTERMEDIARIO	320	t	f
2516	263	85	INTERMEDIARIO	320	t	f
2517	263	86	AVANCADO	321	t	f
2518	263	87	AVANCADO	321	t	f
2519	263	88	INTERMEDIARIO	320	t	f
2520	263	89	AVANCADO	321	t	f
2521	263	90	AVANCADO	321	t	f
2522	263	91	AVANCADO	321	t	f
2523	263	92	AVANCADO	321	t	f
2524	263	93	INTERMEDIARIO	320	t	f
2525	263	94	AVANCADO	321	t	f
2526	263	95	BASICO	318	t	f
2527	263	96	BASICO	318	t	f
2528	263	97	BASICO	318	t	f
2529	263	130	INTERMEDIARIO	320	t	f
2530	263	113	AVANCADO	321	t	f
2531	263	114	AVANCADO	321	t	f
2532	263	115	AVANCADO	321	t	f
2533	263	116	AVANCADO	321	t	f
2534	263	117	AVANCADO	321	t	f
2535	263	118	AVANCADO	321	t	f
2536	263	120	AVANCADO	321	t	f
2537	263	121	INTERMEDIARIO	320	t	f
2538	263	122	INTERMEDIARIO	320	t	f
2539	263	123	INTERMEDIARIO	320	t	f
2540	263	124	INTERMEDIARIO	320	t	f
2541	263	125	BASICO	318	t	f
2542	263	126	BASICO	318	t	f
2543	263	127	AVANCADO	321	t	f
2544	263	129	AVANCADO	321	t	f
2545	263	1	AVANCADO	321	t	f
2546	263	2	INTERMEDIARIO	320	t	f
2547	263	3	INTERMEDIARIO	320	t	f
2548	263	4	AVANCADO	321	t	f
2549	263	5	AVANCADO	321	t	f
2550	263	6	AVANCADO	321	t	f
2551	263	7	AVANCADO	321	t	f
2552	263	8	AVANCADO	321	t	f
2553	263	9	AVANCADO	321	t	f
2554	263	10	AVANCADO	321	t	f
2555	263	11	AVANCADO	321	t	f
2556	263	12	AVANCADO	321	t	f
2557	263	65	AVANCADO	321	t	f
2558	263	66	AVANCADO	321	t	f
2559	263	67	AVANCADO	321	t	f
2560	263	68	INTERMEDIARIO	320	t	f
2561	263	70	INTERMEDIARIO	320	t	f
2562	263	71	AVANCADO	321	t	f
2563	263	72	AVANCADO	321	t	f
2564	263	73	INTERMEDIARIO	320	t	f
2565	263	74	AVANCADO	321	t	f
2566	263	75	AVANCADO	321	t	f
2567	263	76	AVANCADO	321	t	f
2568	263	77	AVANCADO	321	t	f
2569	263	78	INTERMEDIARIO	320	t	f
2570	263	79	INTERMEDIARIO	320	t	f
2571	263	81	INTERMEDIARIO	320	t	f
2572	263	82	AVANCADO	321	t	f
2573	263	108	AVANCADO	321	t	f
2574	263	109	AVANCADO	321	t	f
2575	263	110	AVANCADO	321	t	f
2576	263	111	AVANCADO	321	t	f
2577	263	112	AVANCADO	321	t	f
2578	138	102	INTERMEDIARIO	320	t	f
2579	138	104	AVANCADO	321	t	f
2580	138	106	INTERMEDIARIO	320	t	f
2581	138	107	AVANCADO	321	t	f
2582	138	49	INTERMEDIARIO	320	t	f
2583	138	50	BASICO	318	t	f
2584	138	51	INTERMEDIARIO	320	t	f
2585	138	52	INTERMEDIARIO	320	t	f
2586	138	29	INTERMEDIARIO	320	t	f
2587	138	33	BASICO	318	t	f
2588	138	34	INTERMEDIARIO	320	t	f
2589	138	36	BASICO	318	t	f
2590	138	37	BASICO	318	t	f
2591	138	38	AVANCADO	321	t	f
2592	138	39	INTERMEDIARIO	320	t	f
2593	138	40	BASICO	318	t	f
2594	138	41	BASICO	318	t	f
2595	138	42	INTERMEDIARIO	320	t	f
2596	138	43	INTERMEDIARIO	320	t	f
2597	138	44	BASICO	318	t	f
2598	138	14	BASICO	318	t	f
2599	138	16	AVANCADO	321	t	f
2600	138	19	BASICO	318	t	f
2601	138	21	BASICO	318	t	f
2602	138	23	INTERMEDIARIO	320	t	f
2603	138	26	AVANCADO	321	t	f
2604	138	53	INTERMEDIARIO	320	t	f
2605	138	55	INTERMEDIARIO	320	t	f
2606	138	56	AVANCADO	321	t	f
2607	138	58	INTERMEDIARIO	320	t	f
2608	138	59	INTERMEDIARIO	320	t	f
2609	138	61	INTERMEDIARIO	320	t	f
2610	138	87	BASICO	318	t	f
2611	138	94	BASICO	318	t	f
2612	138	113	INTERMEDIARIO	320	t	f
2613	138	114	INTERMEDIARIO	320	t	f
2614	138	115	AVANCADO	321	t	f
2615	138	116	AVANCADO	321	t	f
2616	138	117	BASICO	318	t	f
2617	138	118	BASICO	318	t	f
2618	138	119	INTERMEDIARIO	320	t	f
2619	138	120	INTERMEDIARIO	320	t	f
2620	138	121	BASICO	318	t	f
2621	138	123	BASICO	318	t	f
2622	138	124	INTERMEDIARIO	320	t	f
2623	138	129	AVANCADO	321	t	f
2624	138	1	INTERMEDIARIO	320	t	f
2625	138	4	INTERMEDIARIO	320	t	f
2626	138	8	INTERMEDIARIO	320	t	f
2627	138	9	AVANCADO	321	t	f
2628	138	12	AVANCADO	321	t	f
2629	138	63	BASICO	318	t	f
2630	138	65	AVANCADO	321	t	f
2631	138	66	INTERMEDIARIO	320	t	f
2632	138	67	BASICO	318	t	f
2633	138	71	BASICO	318	t	f
2634	138	72	INTERMEDIARIO	320	t	f
2635	138	73	INTERMEDIARIO	320	t	f
2636	138	75	INTERMEDIARIO	320	t	f
2637	138	76	AVANCADO	321	t	f
2638	138	82	INTERMEDIARIO	320	t	f
2639	138	108	AVANCADO	321	t	f
2640	138	109	AVANCADO	321	t	f
2641	138	110	BASICO	318	t	f
2642	138	111	INTERMEDIARIO	320	t	f
2643	202	100	INTERMEDIARIO	320	t	f
2644	202	102	INTERMEDIARIO	320	t	f
2645	202	107	AVANCADO	321	t	f
2646	202	47	INTERMEDIARIO	320	t	f
2647	202	48	AVANCADO	321	t	f
2648	202	50	BASICO	318	t	f
2649	202	29	BASICO	318	t	f
2650	202	39	BASICO	318	t	f
2651	202	40	BASICO	318	t	f
2652	202	41	BASICO	318	t	f
2653	202	130	BASICO	318	t	f
2654	202	2	INTERMEDIARIO	320	t	f
2655	202	3	INTERMEDIARIO	320	t	f
2656	202	12	AVANCADO	321	t	f
2657	160	104	BASICO	318	t	f
2658	160	105	INTERMEDIARIO	320	t	f
2659	160	106	INTERMEDIARIO	320	t	f
2660	160	107	BASICO	318	t	f
2661	160	49	BASICO	318	t	f
2662	160	50	INTERMEDIARIO	320	t	f
2663	160	51	BASICO	318	t	f
2664	160	52	INTERMEDIARIO	320	t	f
2665	160	29	BASICO	318	t	f
2666	160	36	BASICO	318	t	f
2667	160	18	BASICO	318	t	f
2668	160	19	BASICO	318	t	f
2669	160	55	AVANCADO	321	t	f
2670	160	56	AVANCADO	321	t	f
2671	160	58	AVANCADO	321	t	f
2672	160	59	AVANCADO	321	t	f
2673	160	60	INTERMEDIARIO	320	t	f
2674	160	61	AVANCADO	321	t	f
2675	160	115	INTERMEDIARIO	320	t	f
2676	160	117	INTERMEDIARIO	320	t	f
2677	160	119	INTERMEDIARIO	320	t	f
2678	160	129	INTERMEDIARIO	320	t	f
2679	160	4	AVANCADO	321	t	f
2680	160	7	AVANCADO	321	t	f
2681	160	8	AVANCADO	321	t	f
2682	160	9	AVANCADO	321	t	f
2683	160	65	INTERMEDIARIO	320	t	f
2684	160	66	INTERMEDIARIO	320	t	f
2685	160	109	INTERMEDIARIO	320	t	f
2686	160	110	INTERMEDIARIO	320	t	f
2687	160	111	INTERMEDIARIO	320	t	f
2688	87	98	BASICO	318	t	f
2689	87	99	BASICO	318	t	f
2690	87	100	BASICO	318	t	f
2691	87	101	BASICO	318	t	f
2692	87	102	INTERMEDIARIO	320	t	f
2693	87	103	BASICO	318	t	f
2694	87	104	BASICO	318	t	f
2695	87	105	BASICO	318	t	f
2696	87	106	INTERMEDIARIO	320	t	f
2697	87	107	BASICO	318	t	f
2698	87	47	BASICO	318	t	f
2699	87	48	BASICO	318	t	f
2700	87	49	BASICO	318	t	f
2701	87	50	BASICO	318	t	f
2702	87	51	BASICO	318	t	f
2703	87	52	BASICO	318	t	f
2704	87	28	BASICO	318	t	f
2705	87	29	BASICO	318	t	f
2706	87	30	INTERMEDIARIO	320	t	f
2707	87	31	BASICO	318	t	f
2708	87	32	BASICO	318	t	f
2709	87	33	BASICO	318	t	f
2710	87	34	BASICO	318	t	f
2711	87	35	BASICO	318	t	f
2712	87	36	BASICO	318	t	f
2713	87	37	BASICO	318	t	f
2714	87	38	BASICO	318	t	f
2715	87	39	BASICO	318	t	f
2716	87	40	INTERMEDIARIO	320	t	f
2717	87	41	INTERMEDIARIO	320	t	f
2718	87	42	BASICO	318	t	f
2719	87	43	BASICO	318	t	f
2720	87	44	BASICO	318	t	f
2721	87	45	BASICO	318	t	f
2722	87	46	BASICO	318	t	f
2723	87	13	BASICO	318	t	f
2724	87	14	INTERMEDIARIO	320	t	f
2725	87	15	BASICO	318	t	f
2726	87	16	BASICO	318	t	f
2727	87	17	BASICO	318	t	f
2728	87	18	BASICO	318	t	f
2729	87	19	BASICO	318	t	f
2730	87	20	BASICO	318	t	f
2731	87	21	INTERMEDIARIO	320	t	f
2732	87	22	BASICO	318	t	f
2733	87	23	BASICO	318	t	f
2734	87	24	BASICO	318	t	f
2735	87	25	BASICO	318	t	f
2736	87	26	BASICO	318	t	f
2737	87	27	BASICO	318	t	f
2738	87	53	BASICO	318	t	f
2739	87	54	BASICO	318	t	f
2740	87	55	INTERMEDIARIO	320	t	f
2741	87	56	INTERMEDIARIO	320	t	f
2742	87	57	BASICO	318	t	f
2743	87	58	INTERMEDIARIO	320	t	f
2744	87	59	BASICO	318	t	f
2745	87	60	BASICO	318	t	f
2746	87	61	INTERMEDIARIO	320	t	f
2747	87	62	BASICO	318	t	f
2748	87	83	BASICO	318	t	f
2749	87	84	INTERMEDIARIO	320	t	f
2750	87	85	BASICO	318	t	f
2751	87	86	BASICO	318	t	f
2752	87	87	INTERMEDIARIO	320	t	f
2753	87	88	AVANCADO	321	t	f
2754	87	89	AVANCADO	321	t	f
2755	87	90	BASICO	318	t	f
2756	87	91	BASICO	318	t	f
2757	87	92	AVANCADO	321	t	f
2758	87	93	BASICO	318	t	f
2759	87	94	AVANCADO	321	t	f
2760	87	95	BASICO	318	t	f
2761	87	96	BASICO	318	t	f
2762	87	97	BASICO	318	t	f
2763	87	130	BASICO	318	t	f
2764	87	113	BASICO	318	t	f
2765	87	114	INTERMEDIARIO	320	t	f
2766	87	115	INTERMEDIARIO	320	t	f
2767	87	116	INTERMEDIARIO	320	t	f
2768	87	117	INTERMEDIARIO	320	t	f
2769	87	118	INTERMEDIARIO	320	t	f
2770	87	119	INTERMEDIARIO	320	t	f
2771	87	120	INTERMEDIARIO	320	t	f
2772	87	121	BASICO	318	t	f
2773	87	122	BASICO	318	t	f
2774	87	123	BASICO	318	t	f
2775	87	124	BASICO	318	t	f
2776	87	125	BASICO	318	t	f
2777	87	126	BASICO	318	t	f
2778	87	127	BASICO	318	t	f
2779	87	129	BASICO	318	t	f
2780	87	1	BASICO	318	t	f
2781	87	2	BASICO	318	t	f
2782	87	3	BASICO	318	t	f
2783	87	4	BASICO	318	t	f
2784	87	5	BASICO	318	t	f
2785	87	6	BASICO	318	t	f
2786	87	7	BASICO	318	t	f
2787	87	8	BASICO	318	t	f
2788	87	9	BASICO	318	t	f
2789	87	10	BASICO	318	t	f
2790	87	11	BASICO	318	t	f
2791	87	12	BASICO	318	t	f
2792	87	63	BASICO	318	t	f
2793	87	64	BASICO	318	t	f
2794	87	65	BASICO	318	t	f
2795	87	66	BASICO	318	t	f
2796	87	67	BASICO	318	t	f
2797	87	68	BASICO	318	t	f
2798	87	69	BASICO	318	t	f
2799	87	70	BASICO	318	t	f
2800	87	71	BASICO	318	t	f
2801	87	72	BASICO	318	t	f
2802	87	73	BASICO	318	t	f
2803	87	74	BASICO	318	t	f
2804	87	75	BASICO	318	t	f
2805	87	76	BASICO	318	t	f
2806	87	77	BASICO	318	t	f
2807	87	78	BASICO	318	t	f
2808	87	79	BASICO	318	t	f
2809	87	81	BASICO	318	t	f
2810	87	82	BASICO	318	t	f
2811	87	108	BASICO	318	t	f
2812	87	109	BASICO	318	t	f
2813	87	110	INTERMEDIARIO	320	t	f
2814	87	111	BASICO	318	t	f
2815	87	112	BASICO	318	t	f
2816	194	98	INTERMEDIARIO	320	t	f
2817	194	99	AVANCADO	321	t	f
2818	194	100	AVANCADO	321	t	f
2819	194	101	BASICO	318	t	f
2820	194	102	BASICO	318	t	f
2821	194	103	BASICO	318	t	f
2822	194	104	INTERMEDIARIO	320	t	f
2823	194	105	INTERMEDIARIO	320	t	f
2824	194	106	INTERMEDIARIO	320	t	f
2825	194	107	INTERMEDIARIO	320	t	f
2826	194	48	INTERMEDIARIO	320	t	f
2827	194	49	BASICO	318	t	f
2828	194	50	BASICO	318	t	f
2829	194	51	BASICO	318	t	f
2830	194	29	BASICO	318	t	f
2831	194	36	BASICO	318	t	f
2832	194	41	BASICO	318	t	f
2833	194	20	BASICO	318	t	f
2834	194	56	BASICO	318	t	f
2835	194	58	BASICO	318	t	f
2836	194	94	BASICO	318	t	f
2837	194	115	BASICO	318	t	f
2838	194	117	BASICO	318	t	f
2839	194	2	INTERMEDIARIO	320	t	f
2840	194	12	BASICO	318	t	f
2841	194	108	BASICO	318	t	f
2842	130	98	INTERMEDIARIO	320	t	f
2843	130	99	BASICO	318	t	f
2844	130	100	BASICO	318	t	f
2845	130	101	BASICO	318	t	f
2846	130	102	BASICO	318	t	f
2847	130	103	INTERMEDIARIO	320	t	f
2848	130	104	BASICO	318	t	f
2849	130	105	BASICO	318	t	f
2850	130	106	INTERMEDIARIO	320	t	f
2851	130	107	INTERMEDIARIO	320	t	f
2852	130	47	BASICO	318	t	f
2853	130	48	BASICO	318	t	f
2854	130	49	INTERMEDIARIO	320	t	f
2855	130	50	INTERMEDIARIO	320	t	f
2856	130	52	BASICO	318	t	f
2857	130	28	INTERMEDIARIO	320	t	f
2858	130	29	INTERMEDIARIO	320	t	f
2859	130	30	INTERMEDIARIO	320	t	f
2860	130	31	BASICO	318	t	f
2861	130	32	BASICO	318	t	f
2862	130	33	INTERMEDIARIO	320	t	f
2863	130	34	INTERMEDIARIO	320	t	f
2864	130	35	INTERMEDIARIO	320	t	f
2865	130	36	AVANCADO	321	t	f
2866	130	37	INTERMEDIARIO	320	t	f
2867	130	38	BASICO	318	t	f
2868	130	39	BASICO	318	t	f
2869	130	40	AVANCADO	321	t	f
2870	130	42	INTERMEDIARIO	320	t	f
2871	130	43	INTERMEDIARIO	320	t	f
2872	130	44	AVANCADO	321	t	f
2873	130	45	BASICO	318	t	f
2874	130	46	BASICO	318	t	f
2875	130	14	INTERMEDIARIO	320	t	f
2876	130	16	BASICO	318	t	f
2877	130	17	BASICO	318	t	f
2878	130	18	BASICO	318	t	f
2879	130	20	BASICO	318	t	f
2880	130	21	INTERMEDIARIO	320	t	f
2881	130	22	BASICO	318	t	f
2882	130	23	BASICO	318	t	f
2883	130	24	BASICO	318	t	f
2884	130	25	BASICO	318	t	f
2885	130	26	BASICO	318	t	f
2886	130	27	BASICO	318	t	f
2887	130	53	BASICO	318	t	f
2888	130	54	BASICO	318	t	f
2889	130	57	BASICO	318	t	f
2890	130	60	INTERMEDIARIO	320	t	f
2891	130	62	INTERMEDIARIO	320	t	f
2892	130	83	BASICO	318	t	f
2893	130	84	BASICO	318	t	f
2894	130	85	BASICO	318	t	f
2895	130	86	AVANCADO	321	t	f
2896	130	87	BASICO	318	t	f
2897	130	88	INTERMEDIARIO	320	t	f
2898	130	89	BASICO	318	t	f
2899	130	90	BASICO	318	t	f
2900	130	91	BASICO	318	t	f
2901	130	92	BASICO	318	t	f
2902	130	93	BASICO	318	t	f
2903	130	94	INTERMEDIARIO	320	t	f
2904	130	95	BASICO	318	t	f
2905	130	96	BASICO	318	t	f
2906	130	97	BASICO	318	t	f
2907	130	130	BASICO	318	t	f
2908	130	113	INTERMEDIARIO	320	t	f
2909	130	114	INTERMEDIARIO	320	t	f
2910	130	117	AVANCADO	321	t	f
2911	130	118	INTERMEDIARIO	320	t	f
2912	130	119	AVANCADO	321	t	f
2913	130	120	INTERMEDIARIO	320	t	f
2914	130	122	BASICO	318	t	f
2915	130	123	BASICO	318	t	f
2916	130	124	BASICO	318	t	f
2917	130	125	BASICO	318	t	f
2918	130	126	BASICO	318	t	f
2919	130	127	BASICO	318	t	f
2920	130	129	INTERMEDIARIO	320	t	f
2921	130	1	INTERMEDIARIO	320	t	f
2922	130	2	BASICO	318	t	f
2923	130	3	BASICO	318	t	f
2924	130	5	BASICO	318	t	f
2925	130	6	BASICO	318	t	f
2926	130	7	BASICO	318	t	f
2927	130	8	INTERMEDIARIO	320	t	f
2928	130	9	INTERMEDIARIO	320	t	f
2929	130	10	INTERMEDIARIO	320	t	f
2930	130	11	BASICO	318	t	f
2931	130	12	INTERMEDIARIO	320	t	f
2932	130	63	BASICO	318	t	f
2933	130	64	BASICO	318	t	f
2934	130	66	INTERMEDIARIO	320	t	f
2935	130	67	BASICO	318	t	f
2936	130	68	BASICO	318	t	f
2937	130	69	BASICO	318	t	f
2938	130	70	BASICO	318	t	f
2939	130	71	BASICO	318	t	f
2940	130	72	INTERMEDIARIO	320	t	f
2941	130	73	BASICO	318	t	f
2942	130	74	BASICO	318	t	f
2943	130	75	BASICO	318	t	f
2944	130	76	BASICO	318	t	f
2945	130	77	BASICO	318	t	f
2946	130	78	BASICO	318	t	f
2947	130	79	BASICO	318	t	f
2948	130	81	BASICO	318	t	f
2949	130	82	BASICO	318	t	f
2950	130	108	AVANCADO	321	t	f
2951	130	109	AVANCADO	321	t	f
2952	130	110	INTERMEDIARIO	320	t	f
2953	130	111	AVANCADO	321	t	f
2954	130	112	INTERMEDIARIO	320	t	f
2955	312	105	BASICO	318	t	f
2956	312	106	AVANCADO	321	t	f
2957	312	107	INTERMEDIARIO	320	t	f
2958	312	49	BASICO	318	t	f
2959	312	50	INTERMEDIARIO	320	t	f
2960	312	51	BASICO	318	t	f
2961	312	52	BASICO	318	t	f
2962	312	36	INTERMEDIARIO	320	t	f
2963	312	37	BASICO	318	t	f
2964	312	38	BASICO	318	t	f
2965	312	41	BASICO	318	t	f
2966	312	15	BASICO	318	t	f
2967	312	19	BASICO	318	t	f
2968	312	55	INTERMEDIARIO	320	t	f
2969	312	56	INTERMEDIARIO	320	t	f
2970	312	58	BASICO	318	t	f
2971	312	113	BASICO	318	t	f
2972	312	115	BASICO	318	t	f
2973	312	117	INTERMEDIARIO	320	t	f
2974	312	129	BASICO	318	t	f
2975	312	9	BASICO	318	t	f
2976	240	98	BASICO	318	t	f
2977	240	105	BASICO	318	t	f
2978	240	106	INTERMEDIARIO	320	t	f
2979	240	50	BASICO	318	t	f
2980	240	51	BASICO	318	t	f
2981	23	98	AVANCADO	321	t	f
2982	23	99	BASICO	318	t	f
2983	23	102	INTERMEDIARIO	320	t	f
2984	23	104	AVANCADO	321	t	f
2985	23	105	AVANCADO	321	t	f
2986	23	106	INTERMEDIARIO	320	t	f
2987	23	48	BASICO	318	t	f
2988	23	49	AVANCADO	321	t	f
2989	23	50	INTERMEDIARIO	320	t	f
2990	23	51	INTERMEDIARIO	320	t	f
2991	23	52	BASICO	318	t	f
2992	23	29	INTERMEDIARIO	320	t	f
2993	23	30	BASICO	318	t	f
2994	23	33	BASICO	318	t	f
2995	23	34	INTERMEDIARIO	320	t	f
2996	23	35	AVANCADO	321	t	f
2997	23	36	INTERMEDIARIO	320	t	f
2998	23	40	INTERMEDIARIO	320	t	f
2999	23	41	AVANCADO	321	t	f
3000	23	42	BASICO	318	t	f
3001	23	43	BASICO	318	t	f
3002	23	44	INTERMEDIARIO	320	t	f
3003	23	14	BASICO	318	t	f
3004	23	19	BASICO	318	t	f
3005	23	21	INTERMEDIARIO	320	t	f
3006	23	55	BASICO	318	t	f
3007	23	56	BASICO	318	t	f
3008	23	58	BASICO	318	t	f
3009	23	59	BASICO	318	t	f
3010	23	60	BASICO	318	t	f
3011	23	61	BASICO	318	t	f
3012	23	113	AVANCADO	321	t	f
3013	23	114	INTERMEDIARIO	320	t	f
3014	23	115	AVANCADO	321	t	f
3015	23	116	BASICO	318	t	f
3016	23	117	INTERMEDIARIO	320	t	f
3017	23	118	INTERMEDIARIO	320	t	f
3018	23	119	AVANCADO	321	t	f
3019	23	120	INTERMEDIARIO	320	t	f
3020	23	121	BASICO	318	t	f
3021	23	123	INTERMEDIARIO	320	t	f
3022	23	124	AVANCADO	321	t	f
3023	23	125	BASICO	318	t	f
3024	23	127	INTERMEDIARIO	320	t	f
3025	23	129	AVANCADO	321	t	f
3026	23	8	INTERMEDIARIO	320	t	f
3027	23	63	INTERMEDIARIO	320	t	f
3028	23	64	INTERMEDIARIO	320	t	f
3029	23	65	AVANCADO	321	t	f
3030	23	66	AVANCADO	321	t	f
3031	23	68	INTERMEDIARIO	320	t	f
3032	23	69	INTERMEDIARIO	320	t	f
3033	23	70	BASICO	318	t	f
3034	23	71	INTERMEDIARIO	320	t	f
3035	23	72	AVANCADO	321	t	f
3036	23	73	BASICO	318	t	f
3037	23	74	BASICO	318	t	f
3038	23	75	AVANCADO	321	t	f
3039	23	77	INTERMEDIARIO	320	t	f
3040	23	78	BASICO	318	t	f
3041	23	82	AVANCADO	321	t	f
3042	23	108	BASICO	318	t	f
3043	23	109	INTERMEDIARIO	320	t	f
3044	23	110	BASICO	318	t	f
3045	23	111	INTERMEDIARIO	320	t	f
3046	23	112	AVANCADO	321	t	f
3047	104	98	AVANCADO	321	t	f
3048	104	102	AVANCADO	321	t	f
3049	104	104	AVANCADO	321	t	f
3050	104	105	AVANCADO	321	t	f
3051	104	106	AVANCADO	321	t	f
3052	104	50	AVANCADO	321	f	t
3053	104	51	AVANCADO	321	t	f
3054	104	52	AVANCADO	321	t	f
3055	104	29	INTERMEDIARIO	320	t	f
3056	104	34	INTERMEDIARIO	320	t	f
3057	104	36	INTERMEDIARIO	320	t	f
3058	104	38	INTERMEDIARIO	320	t	f
3059	104	41	AVANCADO	321	f	t
3060	104	42	INTERMEDIARIO	320	t	f
3061	104	44	INTERMEDIARIO	320	t	f
3062	104	14	INTERMEDIARIO	320	t	f
3063	104	15	INTERMEDIARIO	320	t	f
3064	104	21	INTERMEDIARIO	320	t	f
3065	104	23	BASICO	318	t	f
3066	104	26	BASICO	318	t	f
3067	104	86	INTERMEDIARIO	320	t	f
3068	104	114	INTERMEDIARIO	320	t	f
3069	104	116	AVANCADO	321	t	f
3070	104	117	INTERMEDIARIO	320	t	f
3071	104	119	INTERMEDIARIO	320	t	f
3072	104	120	INTERMEDIARIO	320	t	f
3073	104	123	INTERMEDIARIO	320	t	f
3074	104	124	INTERMEDIARIO	320	t	f
3075	104	129	INTERMEDIARIO	320	t	f
3076	104	1	INTERMEDIARIO	320	f	t
3077	104	4	INTERMEDIARIO	320	f	t
3078	104	7	INTERMEDIARIO	320	t	f
3079	104	9	INTERMEDIARIO	320	t	f
3080	104	65	INTERMEDIARIO	320	f	t
3081	104	66	INTERMEDIARIO	320	t	f
3082	104	69	AVANCADO	321	t	f
3083	104	71	INTERMEDIARIO	320	t	f
3084	104	73	BASICO	318	t	f
3085	104	74	BASICO	318	t	f
3086	104	75	INTERMEDIARIO	320	t	f
3087	104	82	AVANCADO	321	t	f
3088	104	108	INTERMEDIARIO	320	t	f
3089	104	109	AVANCADO	321	t	f
3090	104	111	INTERMEDIARIO	320	t	f
3091	104	112	INTERMEDIARIO	320	t	f
3092	307	99	INTERMEDIARIO	320	t	f
3093	307	103	BASICO	318	t	f
3094	307	106	BASICO	318	t	f
3095	307	107	INTERMEDIARIO	320	t	f
3096	307	48	INTERMEDIARIO	320	t	f
3097	307	49	BASICO	318	t	f
3098	307	50	BASICO	318	t	f
3099	307	52	BASICO	318	t	f
3100	307	29	INTERMEDIARIO	320	t	f
3101	307	36	INTERMEDIARIO	320	t	f
3102	307	37	INTERMEDIARIO	320	t	f
3103	307	38	INTERMEDIARIO	320	t	f
3104	307	39	INTERMEDIARIO	320	t	f
3105	307	40	INTERMEDIARIO	320	t	f
3106	307	41	INTERMEDIARIO	320	t	f
3107	307	44	INTERMEDIARIO	320	t	f
3108	307	13	BASICO	318	t	f
3109	307	16	BASICO	318	t	f
3110	307	18	INTERMEDIARIO	320	t	f
3111	307	20	INTERMEDIARIO	320	t	f
3112	307	21	BASICO	318	t	f
3113	307	24	BASICO	318	t	f
3114	307	25	BASICO	318	t	f
3115	307	53	BASICO	318	t	f
3116	307	54	BASICO	318	t	f
3117	307	55	INTERMEDIARIO	320	t	f
3118	307	56	INTERMEDIARIO	320	t	f
3119	307	58	BASICO	318	t	f
3120	307	62	BASICO	318	t	f
3121	307	113	BASICO	318	t	f
3122	307	115	INTERMEDIARIO	320	t	f
3123	307	117	INTERMEDIARIO	320	t	f
3124	307	118	INTERMEDIARIO	320	t	f
3125	307	119	INTERMEDIARIO	320	t	f
3126	307	129	BASICO	318	t	f
3127	307	1	INTERMEDIARIO	320	t	f
3128	307	2	BASICO	318	t	f
3129	307	8	BASICO	318	t	f
3130	307	9	BASICO	318	t	f
3131	307	10	BASICO	318	t	f
3132	307	65	BASICO	318	t	f
3133	307	66	BASICO	318	t	f
3134	307	72	BASICO	318	t	f
3135	307	82	BASICO	318	t	f
3136	307	109	BASICO	318	t	f
3137	307	111	BASICO	318	t	f
3138	124	98	BASICO	318	t	f
3139	124	104	INTERMEDIARIO	320	t	f
3140	124	106	BASICO	318	t	f
3141	124	107	BASICO	318	t	f
3142	124	49	INTERMEDIARIO	320	t	f
3143	124	51	INTERMEDIARIO	320	t	f
3144	124	52	AVANCADO	321	t	f
3145	124	55	INTERMEDIARIO	320	t	f
3146	124	56	INTERMEDIARIO	320	t	f
3147	124	58	BASICO	318	t	f
3148	124	61	BASICO	318	t	f
3149	319	98	INTERMEDIARIO	320	t	f
3150	319	99	INTERMEDIARIO	320	t	f
3151	319	102	INTERMEDIARIO	320	t	f
3152	319	103	INTERMEDIARIO	320	t	f
3153	319	104	INTERMEDIARIO	320	t	f
3154	319	105	AVANCADO	321	t	f
3155	319	106	AVANCADO	321	t	f
3156	319	48	INTERMEDIARIO	320	t	f
3157	319	35	INTERMEDIARIO	320	t	f
3158	319	39	INTERMEDIARIO	320	t	f
3159	319	55	INTERMEDIARIO	320	t	f
3160	319	56	INTERMEDIARIO	320	t	f
3161	319	114	INTERMEDIARIO	320	t	f
3162	319	115	INTERMEDIARIO	320	t	f
3163	319	116	INTERMEDIARIO	320	t	f
3164	319	117	INTERMEDIARIO	320	t	f
3165	319	119	INTERMEDIARIO	320	t	f
3166	319	9	INTERMEDIARIO	320	t	f
3167	319	10	INTERMEDIARIO	320	t	f
3168	319	63	INTERMEDIARIO	320	t	f
3169	319	64	INTERMEDIARIO	320	t	f
3170	148	105	INTERMEDIARIO	320	t	f
3171	148	106	INTERMEDIARIO	320	t	f
3172	148	47	INTERMEDIARIO	320	t	f
3173	148	50	BASICO	318	t	f
3174	148	29	INTERMEDIARIO	320	t	f
3175	148	37	BASICO	318	t	f
3176	148	38	BASICO	318	t	f
3177	148	39	BASICO	318	t	f
3178	148	16	BASICO	318	t	f
3179	148	26	BASICO	318	t	f
3180	148	54	INTERMEDIARIO	320	t	f
3181	148	55	INTERMEDIARIO	320	t	f
3182	148	56	INTERMEDIARIO	320	t	f
3183	148	86	BASICO	318	t	f
3184	148	113	BASICO	318	t	f
3185	148	117	INTERMEDIARIO	320	t	f
3186	148	119	INTERMEDIARIO	320	t	f
3187	148	129	BASICO	318	t	f
3188	148	4	BASICO	318	t	f
3189	148	9	INTERMEDIARIO	320	t	f
3190	148	12	BASICO	318	t	f
3191	148	66	BASICO	318	t	f
3192	148	72	BASICO	318	t	f
3193	148	74	BASICO	318	t	f
3194	148	109	BASICO	318	t	f
3195	148	110	BASICO	318	t	f
3196	208	102	BASICO	318	t	f
3197	208	105	INTERMEDIARIO	320	t	f
3198	208	106	AVANCADO	321	t	f
3199	208	107	INTERMEDIARIO	320	t	f
3200	208	50	INTERMEDIARIO	320	t	f
3201	208	52	INTERMEDIARIO	320	t	f
3202	208	29	INTERMEDIARIO	320	t	f
3203	208	30	BASICO	318	t	f
3204	208	33	AVANCADO	321	t	f
3205	208	34	AVANCADO	321	t	f
3206	208	36	AVANCADO	321	t	f
3207	208	37	AVANCADO	321	t	f
3208	208	40	BASICO	318	t	f
3209	208	41	AVANCADO	321	t	f
3210	208	42	INTERMEDIARIO	320	t	f
3211	208	43	AVANCADO	321	t	f
3212	208	44	INTERMEDIARIO	320	t	f
3213	208	14	AVANCADO	321	t	f
3214	208	15	BASICO	318	t	f
3215	208	16	BASICO	318	t	f
3216	208	17	INTERMEDIARIO	320	t	f
3217	208	19	BASICO	318	t	f
3218	208	21	AVANCADO	321	t	f
3219	208	22	INTERMEDIARIO	320	t	f
3220	208	26	BASICO	318	t	f
3221	208	53	BASICO	318	t	f
3222	208	55	AVANCADO	321	t	f
3223	208	56	AVANCADO	321	t	f
3224	208	58	AVANCADO	321	t	f
3225	208	59	INTERMEDIARIO	320	t	f
3226	208	61	INTERMEDIARIO	320	t	f
3227	208	62	AVANCADO	321	t	f
3228	208	86	AVANCADO	321	t	f
3229	208	97	AVANCADO	321	t	f
3230	208	113	AVANCADO	321	t	f
3231	208	114	INTERMEDIARIO	320	t	f
3232	208	115	AVANCADO	321	t	f
3233	208	116	AVANCADO	321	t	f
3234	208	117	INTERMEDIARIO	320	t	f
3235	208	118	INTERMEDIARIO	320	t	f
3236	208	119	INTERMEDIARIO	320	t	f
3237	208	120	INTERMEDIARIO	320	t	f
3238	208	121	INTERMEDIARIO	320	t	f
3239	208	122	INTERMEDIARIO	320	t	f
3240	208	123	AVANCADO	321	t	f
3241	208	124	INTERMEDIARIO	320	t	f
3242	208	125	INTERMEDIARIO	320	t	f
3243	208	126	BASICO	318	t	f
3244	208	127	INTERMEDIARIO	320	t	f
3245	208	129	AVANCADO	321	t	f
3246	208	1	INTERMEDIARIO	320	t	f
3247	208	2	INTERMEDIARIO	320	t	f
3248	208	3	BASICO	318	t	f
3249	208	4	AVANCADO	321	t	f
3250	208	5	INTERMEDIARIO	320	t	f
3251	208	6	BASICO	318	t	f
3252	208	7	INTERMEDIARIO	320	t	f
3253	208	8	INTERMEDIARIO	320	t	f
3254	208	9	INTERMEDIARIO	320	t	f
3255	208	10	BASICO	318	t	f
3256	208	11	INTERMEDIARIO	320	t	f
3257	208	12	INTERMEDIARIO	320	t	f
3258	208	63	BASICO	318	t	f
3259	208	64	BASICO	318	t	f
3260	208	65	AVANCADO	321	t	f
3261	208	66	AVANCADO	321	t	f
3262	208	67	INTERMEDIARIO	320	t	f
3263	208	71	AVANCADO	321	t	f
3264	208	72	AVANCADO	321	t	f
3265	208	73	INTERMEDIARIO	320	t	f
3266	208	74	BASICO	318	t	f
3267	208	75	INTERMEDIARIO	320	t	f
3268	208	76	BASICO	318	t	f
3269	208	77	BASICO	318	t	f
3270	208	78	BASICO	318	t	f
3271	208	79	BASICO	318	t	f
3272	208	81	INTERMEDIARIO	320	t	f
3273	208	82	INTERMEDIARIO	320	t	f
3274	208	108	INTERMEDIARIO	320	t	f
3275	208	109	INTERMEDIARIO	320	t	f
3276	208	110	INTERMEDIARIO	320	t	f
3277	208	111	INTERMEDIARIO	320	t	f
3278	330	98	BASICO	318	t	f
3279	330	99	BASICO	318	t	f
3280	330	100	BASICO	318	t	f
3281	330	101	BASICO	318	t	f
3282	330	102	BASICO	318	t	f
3283	330	103	BASICO	318	t	f
3284	330	104	AVANCADO	321	t	f
3285	330	105	BASICO	318	t	f
3286	330	106	AVANCADO	321	t	f
3287	330	107	BASICO	318	t	f
3288	330	47	BASICO	318	t	f
3289	330	48	BASICO	318	t	f
3290	330	49	INTERMEDIARIO	320	t	f
3291	330	50	AVANCADO	321	t	f
3292	330	51	INTERMEDIARIO	320	t	f
3293	330	52	INTERMEDIARIO	320	t	f
3294	330	28	BASICO	318	t	f
3295	330	29	AVANCADO	321	t	f
3296	330	30	AVANCADO	321	t	f
3297	330	31	BASICO	318	t	f
3298	330	32	BASICO	318	t	f
3299	330	33	BASICO	318	t	f
3300	330	34	AVANCADO	321	t	f
3301	330	35	BASICO	318	t	f
3302	330	36	AVANCADO	321	t	f
3303	330	37	BASICO	318	t	f
3304	330	38	BASICO	318	t	f
3305	330	39	BASICO	318	t	f
3306	330	40	INTERMEDIARIO	320	t	f
3307	330	41	AVANCADO	321	t	f
3308	330	42	BASICO	318	t	f
3309	330	43	AVANCADO	321	t	f
3310	330	44	AVANCADO	321	t	f
3311	330	45	BASICO	318	t	f
3312	330	46	BASICO	318	t	f
3313	330	13	BASICO	318	t	f
3314	330	14	AVANCADO	321	t	f
3315	330	15	AVANCADO	321	t	f
3316	330	16	INTERMEDIARIO	320	t	f
3317	330	17	BASICO	318	t	f
3318	330	18	BASICO	318	t	f
3319	330	19	AVANCADO	321	t	f
3320	330	20	BASICO	318	t	f
3321	330	21	AVANCADO	321	t	f
3322	330	22	BASICO	318	t	f
3323	330	23	BASICO	318	t	f
3324	330	24	BASICO	318	t	f
3325	330	25	BASICO	318	t	f
3326	330	26	INTERMEDIARIO	320	t	f
3327	330	27	BASICO	318	t	f
3328	330	53	BASICO	318	t	f
3329	330	54	BASICO	318	t	f
3330	330	55	AVANCADO	321	t	f
3331	330	57	BASICO	318	t	f
3332	330	58	AVANCADO	321	t	f
3333	330	59	AVANCADO	321	t	f
3334	330	60	INTERMEDIARIO	320	t	f
3335	330	61	AVANCADO	321	t	f
3336	330	62	BASICO	318	t	f
3337	330	83	BASICO	318	t	f
3338	330	84	AVANCADO	321	t	f
3339	330	85	BASICO	318	t	f
3340	330	86	BASICO	318	t	f
3341	330	87	BASICO	318	t	f
3342	330	88	BASICO	318	t	f
3343	330	89	AVANCADO	321	t	f
3344	330	90	BASICO	318	t	f
3345	330	91	BASICO	318	t	f
3346	330	92	BASICO	318	t	f
3347	330	93	BASICO	318	t	f
3348	330	94	BASICO	318	t	f
3349	330	95	BASICO	318	t	f
3350	330	96	BASICO	318	t	f
3351	330	97	BASICO	318	t	f
3352	330	130	BASICO	318	t	f
3353	330	113	INTERMEDIARIO	320	t	f
3354	330	114	INTERMEDIARIO	320	t	f
3355	330	115	AVANCADO	321	t	f
3356	330	116	BASICO	318	t	f
3357	330	117	AVANCADO	321	t	f
3358	330	118	AVANCADO	321	t	f
3359	330	119	AVANCADO	321	t	f
3360	330	120	BASICO	318	t	f
3361	330	121	BASICO	318	t	f
3362	330	122	BASICO	318	t	f
3363	330	123	BASICO	318	t	f
3364	330	124	BASICO	318	t	f
3365	330	125	BASICO	318	t	f
3366	330	126	BASICO	318	t	f
3367	330	127	BASICO	318	t	f
3368	330	129	AVANCADO	321	t	f
3369	330	1	INTERMEDIARIO	320	t	f
3370	330	2	BASICO	318	t	f
3371	330	3	BASICO	318	t	f
3372	330	4	INTERMEDIARIO	320	t	f
3373	330	5	BASICO	318	t	f
3374	330	6	BASICO	318	t	f
3375	330	7	BASICO	318	t	f
3376	330	8	INTERMEDIARIO	320	t	f
3377	330	9	INTERMEDIARIO	320	t	f
3378	330	10	BASICO	318	t	f
3379	330	11	BASICO	318	t	f
3380	330	12	BASICO	318	t	f
3381	330	63	BASICO	318	t	f
3382	330	64	BASICO	318	t	f
3383	330	65	AVANCADO	321	t	f
3384	330	66	AVANCADO	321	t	f
3385	330	67	BASICO	318	t	f
3386	330	68	BASICO	318	t	f
3387	330	69	BASICO	318	t	f
3388	330	70	BASICO	318	t	f
3389	330	71	BASICO	318	t	f
3390	330	72	AVANCADO	321	t	f
3391	330	73	BASICO	318	t	f
3392	330	74	BASICO	318	t	f
3393	330	75	BASICO	318	t	f
3394	330	76	BASICO	318	t	f
3395	330	77	BASICO	318	t	f
3396	330	78	BASICO	318	t	f
3397	330	79	BASICO	318	t	f
3398	330	81	BASICO	318	t	f
3399	330	82	BASICO	318	t	f
3400	330	108	INTERMEDIARIO	320	t	f
3401	330	109	INTERMEDIARIO	320	t	f
3402	330	110	INTERMEDIARIO	320	t	f
3403	330	111	INTERMEDIARIO	320	t	f
3404	330	112	INTERMEDIARIO	320	t	f
3405	297	98	BASICO	318	t	f
3406	297	99	BASICO	318	t	f
3407	297	100	BASICO	318	t	f
3408	297	101	BASICO	318	t	f
3409	297	102	BASICO	318	t	f
3410	297	103	INTERMEDIARIO	320	t	f
3411	297	105	BASICO	318	t	f
3412	297	106	INTERMEDIARIO	320	t	f
3413	297	107	INTERMEDIARIO	320	t	f
3414	297	47	BASICO	318	t	f
3415	297	48	BASICO	318	t	f
3416	297	49	BASICO	318	t	f
3417	297	50	INTERMEDIARIO	320	t	f
3418	297	51	BASICO	318	t	f
3419	297	52	INTERMEDIARIO	320	t	f
3420	297	28	BASICO	318	t	f
3421	297	29	INTERMEDIARIO	320	t	f
3422	297	30	BASICO	318	t	f
3423	297	31	BASICO	318	t	f
3424	297	32	BASICO	318	t	f
3425	297	33	BASICO	318	t	f
3426	297	34	INTERMEDIARIO	320	t	f
3427	297	35	INTERMEDIARIO	320	t	f
3428	297	36	INTERMEDIARIO	320	t	f
3429	297	37	INTERMEDIARIO	320	t	f
3430	297	38	INTERMEDIARIO	320	t	f
3431	297	39	INTERMEDIARIO	320	t	f
3432	297	40	INTERMEDIARIO	320	t	f
3433	297	41	INTERMEDIARIO	320	t	f
3434	297	42	BASICO	318	t	f
3435	297	43	INTERMEDIARIO	320	t	f
3436	297	44	BASICO	318	t	f
3437	297	45	BASICO	318	t	f
3438	297	46	BASICO	318	t	f
3439	297	13	BASICO	318	t	f
3440	297	14	INTERMEDIARIO	320	t	f
3441	297	15	BASICO	318	t	f
3442	297	16	INTERMEDIARIO	320	t	f
3443	297	17	INTERMEDIARIO	320	t	f
3444	297	18	BASICO	318	t	f
3445	297	19	BASICO	318	t	f
3446	297	20	BASICO	318	t	f
3447	297	21	INTERMEDIARIO	320	t	f
3448	297	22	INTERMEDIARIO	320	t	f
3449	297	23	INTERMEDIARIO	320	t	f
3450	297	24	BASICO	318	t	f
3451	297	25	BASICO	318	t	f
3452	297	26	INTERMEDIARIO	320	t	f
3453	297	27	INTERMEDIARIO	320	t	f
3454	297	53	BASICO	318	t	f
3455	297	54	BASICO	318	t	f
3456	297	55	BASICO	318	t	f
3457	297	56	BASICO	318	t	f
3458	297	57	BASICO	318	t	f
3459	297	58	BASICO	318	t	f
3460	297	59	BASICO	318	t	f
3461	297	60	BASICO	318	t	f
3462	297	61	BASICO	318	t	f
3463	297	62	BASICO	318	t	f
3464	297	83	BASICO	318	t	f
3465	297	84	BASICO	318	t	f
3466	297	85	BASICO	318	t	f
3467	297	86	INTERMEDIARIO	320	t	f
3468	297	87	BASICO	318	t	f
3469	297	88	BASICO	318	t	f
3470	297	89	INTERMEDIARIO	320	t	f
3471	297	90	BASICO	318	t	f
3472	297	91	BASICO	318	t	f
3473	297	92	BASICO	318	t	f
3474	297	93	BASICO	318	t	f
3475	297	94	BASICO	318	t	f
3476	297	95	BASICO	318	t	f
3477	297	96	BASICO	318	t	f
3478	297	97	BASICO	318	t	f
3479	297	130	BASICO	318	t	f
3480	297	113	INTERMEDIARIO	320	t	f
3481	297	114	INTERMEDIARIO	320	t	f
3482	297	115	INTERMEDIARIO	320	t	f
3483	297	116	INTERMEDIARIO	320	t	f
3484	297	117	INTERMEDIARIO	320	t	f
3485	297	118	INTERMEDIARIO	320	t	f
3486	297	119	INTERMEDIARIO	320	t	f
3487	297	120	INTERMEDIARIO	320	t	f
3488	297	121	BASICO	318	t	f
3489	297	122	BASICO	318	t	f
3490	297	123	INTERMEDIARIO	320	t	f
3491	297	124	BASICO	318	t	f
3492	297	125	BASICO	318	t	f
3493	297	126	BASICO	318	t	f
3494	297	127	BASICO	318	t	f
3495	297	129	INTERMEDIARIO	320	t	f
3496	297	1	INTERMEDIARIO	320	t	f
3497	297	2	BASICO	318	t	f
3498	297	3	BASICO	318	t	f
3499	297	4	INTERMEDIARIO	320	t	f
3500	297	5	BASICO	318	t	f
3501	297	6	BASICO	318	t	f
3502	297	7	BASICO	318	t	f
3503	297	8	INTERMEDIARIO	320	t	f
3504	297	9	INTERMEDIARIO	320	t	f
3505	297	10	BASICO	318	t	f
3506	297	11	BASICO	318	t	f
3507	297	12	INTERMEDIARIO	320	t	f
3508	297	63	INTERMEDIARIO	320	t	f
3509	297	64	INTERMEDIARIO	320	t	f
3510	297	65	INTERMEDIARIO	320	t	f
3511	297	66	INTERMEDIARIO	320	t	f
3512	297	67	BASICO	318	t	f
3513	297	68	INTERMEDIARIO	320	t	f
3514	297	69	BASICO	318	t	f
3515	297	70	BASICO	318	t	f
3516	297	71	INTERMEDIARIO	320	t	f
3517	297	72	INTERMEDIARIO	320	t	f
3518	297	73	INTERMEDIARIO	320	t	f
3519	297	74	BASICO	318	t	f
3520	297	75	BASICO	318	t	f
3521	297	76	BASICO	318	t	f
3522	297	77	BASICO	318	t	f
3523	297	79	BASICO	318	t	f
3524	297	81	BASICO	318	t	f
3525	297	82	INTERMEDIARIO	320	t	f
3526	297	108	BASICO	318	t	f
3527	297	109	BASICO	318	t	f
3528	297	110	BASICO	318	t	f
3529	297	111	BASICO	318	t	f
3530	297	112	BASICO	318	t	f
3531	299	47	BASICO	318	t	f
3532	299	48	BASICO	318	t	f
3533	299	49	BASICO	318	t	f
3534	299	50	BASICO	318	t	f
3535	299	51	BASICO	318	t	f
3536	299	52	BASICO	318	t	f
3537	299	29	BASICO	318	t	f
3538	299	34	BASICO	318	t	f
3539	299	36	BASICO	318	t	f
3540	299	37	BASICO	318	t	f
3541	299	38	BASICO	318	t	f
3542	299	40	BASICO	318	t	f
3543	299	41	BASICO	318	t	f
3544	299	14	INTERMEDIARIO	320	t	f
3545	299	16	BASICO	318	t	f
3546	299	17	BASICO	318	t	f
3547	299	19	BASICO	318	t	f
3548	299	21	INTERMEDIARIO	320	t	f
3549	299	26	INTERMEDIARIO	320	t	f
3550	299	55	INTERMEDIARIO	320	t	f
3551	299	56	INTERMEDIARIO	320	t	f
3552	299	58	INTERMEDIARIO	320	t	f
3553	299	59	INTERMEDIARIO	320	t	f
3554	299	60	INTERMEDIARIO	320	t	f
3555	299	61	INTERMEDIARIO	320	t	f
3556	299	62	INTERMEDIARIO	320	t	f
3557	299	89	BASICO	318	t	f
3558	299	91	BASICO	318	t	f
3559	299	113	BASICO	318	t	f
3560	299	114	BASICO	318	t	f
3561	299	115	BASICO	318	t	f
3562	299	116	BASICO	318	t	f
3563	299	117	BASICO	318	t	f
3564	299	119	BASICO	318	t	f
3565	299	120	BASICO	318	t	f
3566	299	123	BASICO	318	t	f
3567	299	129	BASICO	318	t	f
3568	299	1	BASICO	318	t	f
3569	299	8	BASICO	318	t	f
3570	299	12	BASICO	318	t	f
3571	299	63	BASICO	318	t	f
3572	299	65	BASICO	318	t	f
3573	299	66	BASICO	318	t	f
3574	299	71	BASICO	318	t	f
3575	299	72	BASICO	318	t	f
3576	299	82	BASICO	318	t	f
3577	299	108	BASICO	318	t	f
3578	299	109	BASICO	318	t	f
3579	299	110	BASICO	318	t	f
3580	299	111	BASICO	318	t	f
3581	264	98	INTERMEDIARIO	320	t	f
3582	264	102	BASICO	318	t	f
3583	264	105	BASICO	318	t	f
3584	264	106	INTERMEDIARIO	320	t	f
3585	264	107	BASICO	318	t	f
3586	264	49	BASICO	318	t	f
3587	264	52	AVANCADO	321	t	f
3588	264	29	INTERMEDIARIO	320	t	f
3589	264	30	INTERMEDIARIO	320	t	f
3590	264	34	BASICO	318	t	f
3591	264	39	BASICO	318	t	f
3592	264	40	INTERMEDIARIO	320	t	f
3593	264	42	INTERMEDIARIO	320	t	f
3594	264	44	INTERMEDIARIO	320	t	f
3595	264	15	AVANCADO	321	t	f
3596	264	23	INTERMEDIARIO	320	t	f
3597	264	24	BASICO	318	t	f
3598	264	25	BASICO	318	t	f
3599	264	26	INTERMEDIARIO	320	t	f
3600	264	54	INTERMEDIARIO	320	t	f
3601	264	57	INTERMEDIARIO	320	t	f
3602	264	61	AVANCADO	321	t	f
3603	264	62	BASICO	318	t	f
3604	264	113	INTERMEDIARIO	320	t	f
3605	264	114	BASICO	318	t	f
3606	264	117	AVANCADO	321	t	f
3607	264	118	BASICO	318	t	f
3608	264	119	AVANCADO	321	t	f
3609	264	120	BASICO	318	t	f
3610	264	124	BASICO	318	t	f
3611	264	129	BASICO	318	t	f
3612	264	3	INTERMEDIARIO	320	t	f
3613	264	4	AVANCADO	321	t	f
3614	264	7	INTERMEDIARIO	320	t	f
3615	264	8	INTERMEDIARIO	320	t	f
3616	264	9	AVANCADO	321	t	f
3617	264	12	INTERMEDIARIO	320	t	f
3618	264	66	BASICO	318	t	f
3619	264	71	BASICO	318	t	f
3620	264	72	INTERMEDIARIO	320	t	f
3621	264	74	INTERMEDIARIO	320	t	f
3622	264	75	BASICO	318	t	f
3623	264	108	AVANCADO	321	t	f
3624	264	109	AVANCADO	321	t	f
3625	264	110	INTERMEDIARIO	320	t	f
3626	264	111	INTERMEDIARIO	320	t	f
3627	304	98	AVANCADO	321	t	f
3628	304	99	BASICO	318	t	f
3629	304	100	BASICO	318	t	f
3630	304	101	BASICO	318	t	f
3631	304	102	BASICO	318	t	f
3632	304	103	INTERMEDIARIO	320	t	f
3633	304	104	BASICO	318	t	f
3634	304	105	BASICO	318	t	f
3635	304	106	BASICO	318	t	f
3636	304	107	BASICO	318	t	f
3637	304	47	BASICO	318	t	f
3638	304	48	BASICO	318	t	f
3639	304	49	BASICO	318	t	f
3640	304	50	BASICO	318	t	f
3641	304	51	BASICO	318	t	f
3642	304	52	BASICO	318	t	f
3643	304	29	AVANCADO	321	t	f
3644	304	40	AVANCADO	321	t	f
3645	304	41	AVANCADO	321	t	f
3646	304	42	AVANCADO	321	t	f
3647	304	14	AVANCADO	321	t	f
3648	304	16	AVANCADO	321	t	f
3649	304	21	AVANCADO	321	t	f
3650	304	26	AVANCADO	321	t	f
3651	304	55	INTERMEDIARIO	320	t	f
3652	304	56	INTERMEDIARIO	320	t	f
3653	304	62	INTERMEDIARIO	320	t	f
3654	304	84	BASICO	318	t	f
3655	304	114	INTERMEDIARIO	320	t	f
3656	304	115	INTERMEDIARIO	320	t	f
3657	304	116	INTERMEDIARIO	320	t	f
3658	304	117	AVANCADO	321	t	f
3659	304	119	AVANCADO	321	t	f
3660	304	124	INTERMEDIARIO	320	t	f
3661	304	126	INTERMEDIARIO	320	t	f
3662	304	129	INTERMEDIARIO	320	t	f
3663	304	1	INTERMEDIARIO	320	t	f
3664	304	4	INTERMEDIARIO	320	t	f
3665	304	8	INTERMEDIARIO	320	t	f
3666	304	12	INTERMEDIARIO	320	t	f
3667	304	65	INTERMEDIARIO	320	t	f
3668	304	66	INTERMEDIARIO	320	t	f
3669	304	75	INTERMEDIARIO	320	t	f
3670	304	109	INTERMEDIARIO	320	t	f
3671	304	110	INTERMEDIARIO	320	t	f
3672	254	98	BASICO	318	t	f
3673	254	99	INTERMEDIARIO	320	t	f
3674	254	100	INTERMEDIARIO	320	t	f
3675	254	101	INTERMEDIARIO	320	t	f
3676	254	102	INTERMEDIARIO	320	t	f
3677	254	103	INTERMEDIARIO	320	t	f
3678	254	104	INTERMEDIARIO	320	t	f
3679	254	105	INTERMEDIARIO	320	t	f
3680	254	106	INTERMEDIARIO	320	t	f
3681	254	107	AVANCADO	321	t	f
3682	254	47	BASICO	318	t	f
3683	254	48	BASICO	318	t	f
3684	254	49	INTERMEDIARIO	320	t	f
3685	254	50	INTERMEDIARIO	320	t	f
3686	254	51	BASICO	318	t	f
3687	254	52	BASICO	318	t	f
3688	254	28	INTERMEDIARIO	320	t	f
3689	254	29	INTERMEDIARIO	320	t	f
3690	254	30	INTERMEDIARIO	320	t	f
3691	254	31	INTERMEDIARIO	320	t	f
3692	254	32	BASICO	318	t	f
3693	254	33	INTERMEDIARIO	320	t	f
3694	254	34	INTERMEDIARIO	320	t	f
3695	254	35	AVANCADO	321	t	f
3696	254	36	AVANCADO	321	t	f
3697	254	37	AVANCADO	321	t	f
3698	254	38	AVANCADO	321	t	f
3699	254	39	AVANCADO	321	t	f
3700	254	40	INTERMEDIARIO	320	t	f
3701	254	41	INTERMEDIARIO	320	t	f
3702	254	42	INTERMEDIARIO	320	t	f
3703	254	43	INTERMEDIARIO	320	t	f
3704	254	44	INTERMEDIARIO	320	t	f
3705	254	45	INTERMEDIARIO	320	t	f
3706	254	46	INTERMEDIARIO	320	t	f
3707	254	13	INTERMEDIARIO	320	t	f
3708	254	14	INTERMEDIARIO	320	t	f
3709	254	15	INTERMEDIARIO	320	t	f
3710	254	16	INTERMEDIARIO	320	t	f
3711	254	17	INTERMEDIARIO	320	t	f
3712	254	18	INTERMEDIARIO	320	t	f
3713	254	19	INTERMEDIARIO	320	t	f
3714	254	20	INTERMEDIARIO	320	t	f
3715	254	21	INTERMEDIARIO	320	t	f
3716	254	22	INTERMEDIARIO	320	t	f
3717	254	23	INTERMEDIARIO	320	t	f
3718	254	24	BASICO	318	t	f
3719	254	25	BASICO	318	t	f
3720	254	26	INTERMEDIARIO	320	t	f
3721	254	27	BASICO	318	t	f
3722	254	53	INTERMEDIARIO	320	t	f
3723	254	54	INTERMEDIARIO	320	t	f
3724	254	55	INTERMEDIARIO	320	t	f
3725	254	56	INTERMEDIARIO	320	t	f
3726	254	57	INTERMEDIARIO	320	t	f
3727	254	58	INTERMEDIARIO	320	t	f
3728	254	59	INTERMEDIARIO	320	t	f
3729	254	60	INTERMEDIARIO	320	t	f
3730	254	61	INTERMEDIARIO	320	t	f
3731	254	62	INTERMEDIARIO	320	t	f
3732	254	83	BASICO	318	t	f
3733	254	84	BASICO	318	t	f
3734	254	85	BASICO	318	t	f
3735	254	86	BASICO	318	t	f
3736	254	87	BASICO	318	t	f
3737	254	88	BASICO	318	t	f
3738	254	89	BASICO	318	t	f
3739	254	90	BASICO	318	t	f
3740	254	91	BASICO	318	t	f
3741	254	92	BASICO	318	t	f
3742	254	93	BASICO	318	t	f
3743	254	94	BASICO	318	t	f
3744	254	95	BASICO	318	t	f
3745	254	96	BASICO	318	t	f
3746	254	97	BASICO	318	t	f
3747	254	130	BASICO	318	t	f
3748	254	113	INTERMEDIARIO	320	t	f
3749	254	114	INTERMEDIARIO	320	t	f
3750	254	115	INTERMEDIARIO	320	t	f
3751	254	116	INTERMEDIARIO	320	t	f
3752	254	117	INTERMEDIARIO	320	t	f
3753	254	118	INTERMEDIARIO	320	t	f
3754	254	119	INTERMEDIARIO	320	t	f
3755	254	120	INTERMEDIARIO	320	t	f
3756	254	121	INTERMEDIARIO	320	t	f
3757	254	122	INTERMEDIARIO	320	t	f
3758	254	123	INTERMEDIARIO	320	t	f
3759	254	124	INTERMEDIARIO	320	t	f
3760	254	125	INTERMEDIARIO	320	t	f
3761	254	126	INTERMEDIARIO	320	t	f
3762	254	127	INTERMEDIARIO	320	t	f
3763	254	129	INTERMEDIARIO	320	t	f
3764	254	1	AVANCADO	321	t	f
3765	254	2	AVANCADO	321	t	f
3766	254	3	AVANCADO	321	t	f
3767	254	4	INTERMEDIARIO	320	t	f
3768	254	5	INTERMEDIARIO	320	t	f
3769	254	6	BASICO	318	t	f
3770	254	7	BASICO	318	t	f
3771	254	8	INTERMEDIARIO	320	t	f
3772	254	9	AVANCADO	321	t	f
3773	254	10	INTERMEDIARIO	320	t	f
3774	254	11	INTERMEDIARIO	320	t	f
3775	254	12	AVANCADO	321	t	f
3776	254	63	INTERMEDIARIO	320	t	f
3777	254	64	INTERMEDIARIO	320	t	f
3778	254	65	INTERMEDIARIO	320	t	f
3779	254	66	INTERMEDIARIO	320	t	f
3780	254	67	INTERMEDIARIO	320	t	f
3781	254	68	INTERMEDIARIO	320	t	f
3782	254	69	BASICO	318	t	f
3783	254	70	BASICO	318	t	f
3784	254	71	INTERMEDIARIO	320	t	f
3785	254	72	INTERMEDIARIO	320	t	f
3786	254	73	INTERMEDIARIO	320	t	f
3787	254	74	BASICO	318	t	f
3788	254	75	BASICO	318	t	f
3789	254	76	BASICO	318	t	f
3790	254	77	BASICO	318	t	f
3791	254	78	BASICO	318	t	f
3792	254	79	BASICO	318	t	f
3793	254	81	BASICO	318	t	f
3794	254	82	INTERMEDIARIO	320	t	f
3795	254	108	INTERMEDIARIO	320	t	f
3796	254	109	INTERMEDIARIO	320	t	f
3797	254	110	INTERMEDIARIO	320	t	f
3798	254	111	INTERMEDIARIO	320	t	f
3799	254	112	INTERMEDIARIO	320	t	f
3800	267	98	BASICO	318	t	f
3801	267	99	INTERMEDIARIO	320	t	f
3802	267	100	INTERMEDIARIO	320	t	f
3803	267	101	BASICO	318	t	f
3804	267	102	AVANCADO	321	t	f
3805	267	103	BASICO	318	t	f
3806	267	104	INTERMEDIARIO	320	t	f
3807	267	105	BASICO	318	t	f
3808	267	106	AVANCADO	321	t	f
3809	267	107	BASICO	318	t	f
3810	267	48	INTERMEDIARIO	320	t	f
3811	267	49	INTERMEDIARIO	320	t	f
3812	267	50	BASICO	318	t	f
3813	267	51	BASICO	318	t	f
3814	267	52	BASICO	318	t	f
3815	267	30	BASICO	318	t	f
3816	267	33	BASICO	318	t	f
3817	267	35	BASICO	318	t	f
3818	267	36	BASICO	318	t	f
3819	267	40	BASICO	318	t	f
3820	267	44	BASICO	318	t	f
3821	267	18	BASICO	318	t	f
3822	267	19	BASICO	318	t	f
3823	267	20	BASICO	318	t	f
3824	267	21	BASICO	318	t	f
3825	267	55	BASICO	318	t	f
3826	267	56	BASICO	318	t	f
3827	267	59	BASICO	318	t	f
3828	267	60	BASICO	318	t	f
3829	267	61	BASICO	318	t	f
3830	267	62	BASICO	318	t	f
3831	267	83	BASICO	318	t	f
3832	267	84	BASICO	318	t	f
3833	267	1	BASICO	318	t	f
3834	267	10	BASICO	318	t	f
3835	267	12	BASICO	318	t	f
3836	267	64	BASICO	318	t	f
3837	267	65	BASICO	318	t	f
3838	267	66	BASICO	318	t	f
3839	267	67	BASICO	318	t	f
3840	267	82	BASICO	318	t	f
3841	298	98	BASICO	318	t	f
3842	298	99	BASICO	318	t	f
3843	298	100	BASICO	318	t	f
3844	298	101	BASICO	318	t	f
3845	298	102	BASICO	318	t	f
3846	298	103	BASICO	318	t	f
3847	298	104	BASICO	318	t	f
3848	298	105	INTERMEDIARIO	320	t	f
3849	298	106	INTERMEDIARIO	320	t	f
3850	298	107	BASICO	318	t	f
3851	298	47	BASICO	318	t	f
3852	298	48	BASICO	318	t	f
3853	298	49	BASICO	318	t	f
3854	298	50	INTERMEDIARIO	320	t	f
3855	298	51	BASICO	318	t	f
3856	298	52	INTERMEDIARIO	320	t	f
3857	298	28	BASICO	318	t	f
3858	298	29	INTERMEDIARIO	320	t	f
3859	298	30	BASICO	318	t	f
3860	298	31	BASICO	318	t	f
3861	298	32	BASICO	318	t	f
3862	298	33	BASICO	318	t	f
3863	298	34	INTERMEDIARIO	320	t	f
3864	298	35	BASICO	318	t	f
3865	298	36	INTERMEDIARIO	320	t	f
3866	298	37	BASICO	318	t	f
3867	298	38	BASICO	318	t	f
3868	298	39	INTERMEDIARIO	320	t	f
3869	298	40	BASICO	318	t	f
3870	298	41	INTERMEDIARIO	320	t	f
3871	298	42	BASICO	318	t	f
3872	298	43	INTERMEDIARIO	320	t	f
3873	298	44	BASICO	318	t	f
3874	298	45	INTERMEDIARIO	320	t	f
3875	298	46	INTERMEDIARIO	320	t	f
3876	298	13	BASICO	318	t	f
3877	298	14	INTERMEDIARIO	320	t	f
3878	298	15	INTERMEDIARIO	320	t	f
3879	298	16	BASICO	318	t	f
3880	298	17	BASICO	318	t	f
3881	298	18	BASICO	318	t	f
3882	298	19	INTERMEDIARIO	320	t	f
3883	298	20	BASICO	318	t	f
3884	298	21	INTERMEDIARIO	320	t	f
3885	298	22	BASICO	318	t	f
3886	298	23	BASICO	318	t	f
3887	298	24	BASICO	318	t	f
3888	298	25	BASICO	318	t	f
3889	298	26	BASICO	318	t	f
3890	298	27	BASICO	318	t	f
3891	298	53	BASICO	318	t	f
3892	298	54	BASICO	318	t	f
3893	298	55	AVANCADO	321	t	f
3894	298	56	AVANCADO	321	t	f
3895	298	57	BASICO	318	t	f
3896	298	58	INTERMEDIARIO	320	t	f
3897	298	59	AVANCADO	321	t	f
3898	298	60	INTERMEDIARIO	320	t	f
3899	298	61	AVANCADO	321	t	f
3900	298	62	BASICO	318	t	f
3901	298	83	BASICO	318	t	f
3902	298	84	BASICO	318	t	f
3903	298	85	BASICO	318	t	f
3904	298	86	BASICO	318	t	f
3905	298	87	BASICO	318	t	f
3906	298	88	BASICO	318	t	f
3907	298	89	BASICO	318	t	f
3908	298	90	BASICO	318	t	f
3909	298	91	BASICO	318	t	f
3910	298	92	BASICO	318	t	f
3911	298	93	BASICO	318	t	f
3912	298	94	BASICO	318	t	f
3913	298	95	BASICO	318	t	f
3914	298	96	BASICO	318	t	f
3915	298	97	BASICO	318	t	f
3916	298	130	BASICO	318	t	f
3917	298	113	INTERMEDIARIO	320	t	f
3918	298	114	BASICO	318	t	f
3919	298	115	AVANCADO	321	t	f
3920	298	116	BASICO	318	t	f
3921	298	117	INTERMEDIARIO	320	t	f
3922	298	118	BASICO	318	t	f
3923	298	119	AVANCADO	321	t	f
3924	298	120	BASICO	318	t	f
3925	298	122	BASICO	318	t	f
3926	298	123	BASICO	318	t	f
3927	298	124	BASICO	318	t	f
3928	298	125	BASICO	318	t	f
3929	298	126	BASICO	318	t	f
3930	298	127	BASICO	318	t	f
3931	298	129	INTERMEDIARIO	320	t	f
3932	298	1	INTERMEDIARIO	320	t	f
3933	298	2	INTERMEDIARIO	320	t	f
3934	298	3	INTERMEDIARIO	320	t	f
3935	298	4	INTERMEDIARIO	320	t	f
3936	298	5	BASICO	318	t	f
3937	298	6	BASICO	318	t	f
3938	298	7	BASICO	318	t	f
3939	298	8	BASICO	318	t	f
3940	298	9	BASICO	318	t	f
3941	298	10	BASICO	318	t	f
3942	298	11	BASICO	318	t	f
3943	298	12	BASICO	318	t	f
3944	298	63	BASICO	318	t	f
3945	298	64	BASICO	318	t	f
3946	298	65	INTERMEDIARIO	320	t	f
3947	298	66	INTERMEDIARIO	320	t	f
3948	298	67	BASICO	318	t	f
3949	298	68	BASICO	318	t	f
3950	298	69	BASICO	318	t	f
3951	298	70	BASICO	318	t	f
3952	298	71	BASICO	318	t	f
3953	298	72	BASICO	318	t	f
3954	298	73	BASICO	318	t	f
3955	298	74	INTERMEDIARIO	320	t	f
3956	298	75	BASICO	318	t	f
3957	298	76	BASICO	318	t	f
3958	298	77	BASICO	318	t	f
3959	298	78	BASICO	318	t	f
3960	298	79	BASICO	318	t	f
3961	298	81	BASICO	318	t	f
3962	298	82	BASICO	318	t	f
3963	298	108	BASICO	318	t	f
3964	298	109	INTERMEDIARIO	320	t	f
3965	298	110	BASICO	318	t	f
3966	298	111	BASICO	318	t	f
3967	298	112	BASICO	318	t	f
3968	68	99	INTERMEDIARIO	320	t	f
3969	68	101	BASICO	318	t	f
3970	68	102	INTERMEDIARIO	320	t	f
3971	68	104	BASICO	318	t	f
3972	68	105	BASICO	318	t	f
3973	68	106	INTERMEDIARIO	320	t	f
3974	68	50	BASICO	318	t	f
3975	68	40	BASICO	318	t	f
3976	68	87	BASICO	318	t	f
3977	68	114	BASICO	318	t	f
3978	68	115	BASICO	318	t	f
3979	68	119	BASICO	318	t	f
3980	68	2	INTERMEDIARIO	320	t	f
3981	68	9	INTERMEDIARIO	320	t	f
3982	68	12	INTERMEDIARIO	320	t	f
3983	259	99	BASICO	318	t	f
3984	259	100	BASICO	318	t	f
3985	259	101	BASICO	318	t	f
3986	259	103	BASICO	318	t	f
3987	259	104	BASICO	318	t	f
3988	259	105	BASICO	318	t	f
3989	259	107	INTERMEDIARIO	320	t	f
3990	259	47	BASICO	318	t	f
3991	259	48	BASICO	318	t	f
3992	259	49	BASICO	318	t	f
3993	259	50	INTERMEDIARIO	320	t	f
3994	259	51	INTERMEDIARIO	320	t	f
3995	259	52	AVANCADO	321	t	f
3996	259	28	INTERMEDIARIO	320	t	f
3997	259	29	INTERMEDIARIO	320	t	f
3998	259	30	INTERMEDIARIO	320	t	f
3999	259	31	BASICO	318	t	f
4000	259	32	BASICO	318	t	f
4001	259	37	INTERMEDIARIO	320	t	f
4002	259	39	INTERMEDIARIO	320	t	f
4003	259	40	INTERMEDIARIO	320	t	f
4004	259	41	INTERMEDIARIO	320	t	f
4005	259	42	INTERMEDIARIO	320	t	f
4006	259	43	INTERMEDIARIO	320	t	f
4007	259	44	INTERMEDIARIO	320	t	f
4008	259	45	INTERMEDIARIO	320	t	f
4009	259	46	BASICO	318	t	f
4010	259	13	AVANCADO	321	t	f
4011	259	14	BASICO	318	t	f
4012	259	15	AVANCADO	321	t	f
4013	259	17	BASICO	318	t	f
4014	259	20	AVANCADO	321	t	f
4015	259	21	BASICO	318	t	f
4016	259	22	BASICO	318	t	f
4017	259	23	INTERMEDIARIO	320	t	f
4018	259	54	AVANCADO	321	t	f
4019	259	55	AVANCADO	321	t	f
4020	259	57	INTERMEDIARIO	320	t	f
4021	259	58	AVANCADO	321	t	f
4022	259	86	BASICO	318	t	f
4023	259	113	AVANCADO	321	t	f
4024	259	114	AVANCADO	321	t	f
4025	259	115	AVANCADO	321	t	f
4026	259	116	AVANCADO	321	t	f
4027	259	117	AVANCADO	321	t	f
4028	259	118	BASICO	318	t	f
4029	259	124	INTERMEDIARIO	320	t	f
4030	259	126	INTERMEDIARIO	320	t	f
4031	259	129	AVANCADO	321	t	f
4032	259	66	AVANCADO	321	t	f
4033	259	67	INTERMEDIARIO	320	t	f
4034	259	72	AVANCADO	321	t	f
4035	259	109	AVANCADO	321	t	f
4036	259	111	INTERMEDIARIO	320	t	f
4037	250	98	INTERMEDIARIO	320	t	f
4038	250	102	AVANCADO	321	t	f
4039	250	103	INTERMEDIARIO	320	t	f
4040	250	104	INTERMEDIARIO	320	t	f
4041	250	105	INTERMEDIARIO	320	t	f
4042	250	106	INTERMEDIARIO	320	t	f
4043	250	107	AVANCADO	321	t	f
4044	250	49	AVANCADO	321	t	f
4045	250	50	INTERMEDIARIO	320	t	f
4046	250	51	INTERMEDIARIO	320	t	f
4047	250	52	AVANCADO	321	t	f
4048	250	28	AVANCADO	321	t	f
4049	250	29	AVANCADO	321	t	f
4050	250	30	INTERMEDIARIO	320	t	f
4051	250	33	INTERMEDIARIO	320	t	f
4052	250	34	AVANCADO	321	t	f
4053	250	35	AVANCADO	321	t	f
4054	250	36	INTERMEDIARIO	320	t	f
4055	250	37	INTERMEDIARIO	320	t	f
4056	250	38	AVANCADO	321	t	f
4057	250	39	AVANCADO	321	t	f
4058	250	40	AVANCADO	321	t	f
4059	250	41	AVANCADO	321	t	f
4060	250	42	AVANCADO	321	t	f
4061	250	43	INTERMEDIARIO	320	t	f
4062	250	44	AVANCADO	321	t	f
4063	250	16	AVANCADO	321	t	f
4064	250	21	INTERMEDIARIO	320	t	f
4065	250	23	AVANCADO	321	t	f
4066	250	26	AVANCADO	321	t	f
4067	250	53	BASICO	318	t	f
4068	250	54	BASICO	318	t	f
4069	250	55	INTERMEDIARIO	320	t	f
4070	250	56	AVANCADO	321	t	f
4071	250	58	INTERMEDIARIO	320	t	f
4072	250	59	AVANCADO	321	t	f
4073	250	60	INTERMEDIARIO	320	t	f
4074	250	61	INTERMEDIARIO	320	t	f
4075	250	89	INTERMEDIARIO	320	t	f
4076	250	94	AVANCADO	321	t	f
4077	250	114	INTERMEDIARIO	320	t	f
4078	250	115	AVANCADO	321	t	f
4079	250	116	AVANCADO	321	t	f
4080	250	117	AVANCADO	321	t	f
4081	250	118	INTERMEDIARIO	320	t	f
4082	250	119	AVANCADO	321	t	f
4083	250	120	INTERMEDIARIO	320	t	f
4084	250	122	INTERMEDIARIO	320	t	f
4085	250	123	INTERMEDIARIO	320	t	f
4086	250	129	AVANCADO	321	t	f
4087	250	2	INTERMEDIARIO	320	t	f
4088	250	4	AVANCADO	321	t	f
4089	250	5	AVANCADO	321	t	f
4090	250	8	AVANCADO	321	t	f
4091	250	9	AVANCADO	321	t	f
4092	250	12	AVANCADO	321	t	f
4093	250	63	BASICO	318	t	f
4094	250	64	BASICO	318	t	f
4095	250	65	AVANCADO	321	t	f
4096	250	66	AVANCADO	321	t	f
4097	250	71	INTERMEDIARIO	320	t	f
4098	250	72	BASICO	318	t	f
4099	250	74	AVANCADO	321	t	f
4100	250	81	INTERMEDIARIO	320	t	f
4101	250	108	AVANCADO	321	t	f
4102	250	109	AVANCADO	321	t	f
4103	250	110	INTERMEDIARIO	320	t	f
4104	250	111	INTERMEDIARIO	320	t	f
4105	143	98	BASICO	318	t	f
4106	143	99	INTERMEDIARIO	320	t	f
4107	143	100	INTERMEDIARIO	320	t	f
4108	143	102	INTERMEDIARIO	320	t	f
4109	143	103	BASICO	318	t	f
4110	143	104	BASICO	318	t	f
4111	143	105	BASICO	318	t	f
4112	143	106	AVANCADO	321	t	f
4113	143	107	AVANCADO	321	t	f
4114	143	49	INTERMEDIARIO	320	t	f
4115	143	50	INTERMEDIARIO	320	t	f
4116	143	52	INTERMEDIARIO	320	t	f
4117	143	29	AVANCADO	321	t	f
4118	143	31	INTERMEDIARIO	320	t	f
4119	143	36	INTERMEDIARIO	320	t	f
4120	143	37	INTERMEDIARIO	320	t	f
4121	143	40	BASICO	318	t	f
4122	143	41	INTERMEDIARIO	320	t	f
4123	143	42	INTERMEDIARIO	320	t	f
4124	143	43	INTERMEDIARIO	320	t	f
4125	143	44	INTERMEDIARIO	320	t	f
4126	143	46	INTERMEDIARIO	320	t	f
4127	143	13	BASICO	318	t	f
4128	143	14	INTERMEDIARIO	320	t	f
4129	143	15	INTERMEDIARIO	320	t	f
4130	143	16	BASICO	318	t	f
4131	143	18	AVANCADO	321	t	f
4132	143	19	INTERMEDIARIO	320	t	f
4133	143	20	AVANCADO	321	t	f
4134	143	21	INTERMEDIARIO	320	t	f
4135	143	23	BASICO	318	t	f
4136	143	26	BASICO	318	t	f
4137	143	27	BASICO	318	t	f
4138	143	55	AVANCADO	321	t	f
4139	143	56	AVANCADO	321	t	f
4140	143	58	AVANCADO	321	t	f
4141	143	59	INTERMEDIARIO	320	t	f
4142	143	61	INTERMEDIARIO	320	t	f
4143	143	62	INTERMEDIARIO	320	t	f
4144	143	113	AVANCADO	321	t	f
4145	143	114	BASICO	318	t	f
4146	143	115	AVANCADO	321	t	f
4147	143	116	AVANCADO	321	t	f
4148	143	117	AVANCADO	321	t	f
4149	143	118	BASICO	318	t	f
4150	143	119	INTERMEDIARIO	320	t	f
4151	143	124	INTERMEDIARIO	320	t	f
4152	143	129	INTERMEDIARIO	320	t	f
4153	143	1	AVANCADO	321	t	f
4154	143	8	INTERMEDIARIO	320	t	f
4155	143	9	AVANCADO	321	t	f
4156	143	10	INTERMEDIARIO	320	t	f
4157	143	12	AVANCADO	321	t	f
4158	143	63	BASICO	318	t	f
4159	143	64	BASICO	318	t	f
4160	143	65	INTERMEDIARIO	320	t	f
4161	143	66	INTERMEDIARIO	320	t	f
4162	143	68	INTERMEDIARIO	320	t	f
4163	143	72	INTERMEDIARIO	320	t	f
4164	143	74	AVANCADO	321	t	f
4165	143	75	INTERMEDIARIO	320	t	f
4166	143	76	BASICO	318	t	f
4167	143	77	BASICO	318	t	f
4168	143	81	AVANCADO	321	t	f
4169	143	82	AVANCADO	321	t	f
4170	143	108	AVANCADO	321	t	f
4171	143	109	AVANCADO	321	t	f
4172	143	110	AVANCADO	321	t	f
4173	143	111	AVANCADO	321	t	f
4174	16	98	BASICO	318	t	f
4175	16	99	INTERMEDIARIO	320	t	f
4176	16	100	INTERMEDIARIO	320	t	f
4177	16	101	BASICO	318	t	f
4178	16	102	BASICO	318	t	f
4179	16	103	BASICO	318	t	f
4180	16	104	INTERMEDIARIO	320	t	f
4181	16	105	INTERMEDIARIO	320	t	f
4182	16	106	INTERMEDIARIO	320	t	f
4183	16	107	INTERMEDIARIO	320	t	f
4184	16	47	INTERMEDIARIO	320	t	f
4185	16	48	INTERMEDIARIO	320	t	f
4186	16	49	AVANCADO	321	t	f
4187	16	50	INTERMEDIARIO	320	t	f
4188	16	51	AVANCADO	321	t	f
4189	16	52	INTERMEDIARIO	320	t	f
4190	16	28	BASICO	318	t	f
4191	16	29	AVANCADO	321	t	f
4192	16	30	BASICO	318	t	f
4193	16	31	INTERMEDIARIO	320	t	f
4194	16	32	BASICO	318	t	f
4195	16	33	BASICO	318	t	f
4196	16	34	BASICO	318	t	f
4197	16	37	INTERMEDIARIO	320	t	f
4198	16	38	INTERMEDIARIO	320	t	f
4199	16	39	BASICO	318	t	f
4200	16	40	INTERMEDIARIO	320	t	f
4201	16	43	INTERMEDIARIO	320	t	f
4202	16	44	INTERMEDIARIO	320	t	f
4203	16	45	BASICO	318	t	f
4204	16	46	BASICO	318	t	f
4205	16	13	BASICO	318	t	f
4206	16	14	INTERMEDIARIO	320	t	f
4207	16	15	AVANCADO	321	t	f
4208	16	17	BASICO	318	t	f
4209	16	21	AVANCADO	321	t	f
4210	16	22	BASICO	318	t	f
4211	16	24	BASICO	318	t	f
4212	16	25	BASICO	318	t	f
4213	16	27	BASICO	318	t	f
4214	16	54	BASICO	318	t	f
4215	16	57	BASICO	318	t	f
4216	16	60	INTERMEDIARIO	320	t	f
4217	16	62	BASICO	318	t	f
4218	16	83	BASICO	318	t	f
4219	16	84	BASICO	318	t	f
4220	16	85	BASICO	318	t	f
4221	16	86	INTERMEDIARIO	320	t	f
4222	16	89	BASICO	318	t	f
4223	16	91	BASICO	318	t	f
4224	16	92	BASICO	318	t	f
4225	16	93	INTERMEDIARIO	320	t	f
4226	16	94	INTERMEDIARIO	320	t	f
4227	16	96	BASICO	318	t	f
4228	16	97	BASICO	318	t	f
4229	16	130	BASICO	318	t	f
4230	16	113	INTERMEDIARIO	320	t	f
4231	16	116	INTERMEDIARIO	320	t	f
4232	16	117	AVANCADO	321	t	f
4233	16	118	INTERMEDIARIO	320	t	f
4234	16	121	INTERMEDIARIO	320	t	f
4235	16	122	BASICO	318	t	f
4236	16	123	INTERMEDIARIO	320	t	f
4237	16	124	AVANCADO	321	t	f
4238	16	125	INTERMEDIARIO	320	t	f
4239	16	126	AVANCADO	321	t	f
4240	16	129	AVANCADO	321	t	f
4241	16	1	AVANCADO	321	t	f
4242	16	2	INTERMEDIARIO	320	t	f
4243	16	3	INTERMEDIARIO	320	t	f
4244	16	4	INTERMEDIARIO	320	t	f
4245	16	5	INTERMEDIARIO	320	t	f
4246	16	6	INTERMEDIARIO	320	t	f
4247	16	7	BASICO	318	t	f
4248	16	8	INTERMEDIARIO	320	t	f
4249	16	9	AVANCADO	321	t	f
4250	16	10	INTERMEDIARIO	320	t	f
4251	16	11	BASICO	318	t	f
4252	16	12	INTERMEDIARIO	320	t	f
4253	16	64	BASICO	318	t	f
4254	16	68	INTERMEDIARIO	320	t	f
4255	16	72	AVANCADO	321	t	f
4256	16	79	INTERMEDIARIO	320	t	f
4257	16	108	INTERMEDIARIO	320	t	f
4258	16	109	INTERMEDIARIO	320	t	f
4259	16	111	AVANCADO	321	t	f
4260	16	112	INTERMEDIARIO	320	t	f
4261	2	98	INTERMEDIARIO	320	t	f
4262	2	100	AVANCADO	321	t	f
4263	2	101	BASICO	318	t	f
4264	2	104	AVANCADO	321	t	f
4265	2	105	INTERMEDIARIO	320	t	f
4266	2	106	AVANCADO	321	t	f
4267	2	107	INTERMEDIARIO	320	t	f
4268	2	47	BASICO	318	t	f
4269	2	48	AVANCADO	321	t	f
4270	2	49	INTERMEDIARIO	320	t	f
4271	2	51	AVANCADO	321	t	f
4272	2	52	BASICO	318	t	f
4273	2	29	BASICO	318	t	f
4274	2	30	BASICO	318	t	f
4275	2	35	INTERMEDIARIO	320	t	f
4276	2	36	INTERMEDIARIO	320	t	f
4277	2	38	INTERMEDIARIO	320	t	f
4278	2	39	INTERMEDIARIO	320	t	f
4279	2	40	BASICO	318	t	f
4280	2	41	BASICO	318	t	f
4281	2	16	BASICO	318	t	f
4282	2	21	BASICO	318	t	f
4283	2	53	BASICO	318	t	f
4284	2	56	BASICO	318	t	f
4285	2	84	BASICO	318	t	f
4286	2	85	BASICO	318	t	f
4287	2	94	INTERMEDIARIO	320	t	f
4288	2	117	INTERMEDIARIO	320	t	f
4289	2	129	BASICO	318	t	f
4290	2	2	INTERMEDIARIO	320	t	f
4291	2	8	INTERMEDIARIO	320	t	f
4292	2	10	INTERMEDIARIO	320	t	f
4293	2	12	INTERMEDIARIO	320	t	f
4294	2	63	BASICO	318	t	f
4295	2	72	BASICO	318	t	f
4296	2	110	INTERMEDIARIO	320	t	f
4297	212	98	BASICO	318	t	f
4298	212	103	BASICO	318	t	f
4299	212	105	AVANCADO	321	t	f
4300	212	106	AVANCADO	321	t	f
4301	212	107	INTERMEDIARIO	320	t	f
4302	212	49	AVANCADO	321	t	f
4303	212	50	BASICO	318	t	f
4304	212	52	AVANCADO	321	t	f
4305	212	29	AVANCADO	321	t	f
4306	212	30	BASICO	318	t	f
4307	212	34	INTERMEDIARIO	320	t	f
4308	212	35	AVANCADO	321	t	f
4309	212	36	AVANCADO	321	t	f
4310	212	37	AVANCADO	321	t	f
4311	212	38	INTERMEDIARIO	320	t	f
4312	212	39	AVANCADO	321	t	f
4313	212	40	AVANCADO	321	t	f
4314	212	41	AVANCADO	321	t	f
4315	212	42	BASICO	318	t	f
4316	212	43	INTERMEDIARIO	320	t	f
4317	212	44	AVANCADO	321	t	f
4318	212	45	BASICO	318	t	f
4319	212	14	AVANCADO	321	t	f
4320	212	15	AVANCADO	321	t	f
4321	212	17	INTERMEDIARIO	320	t	f
4322	212	19	AVANCADO	321	t	f
4323	212	22	INTERMEDIARIO	320	t	f
4324	212	26	BASICO	318	t	f
4325	212	27	INTERMEDIARIO	320	t	f
4326	212	53	BASICO	318	t	f
4327	212	54	BASICO	318	t	f
4328	212	55	INTERMEDIARIO	320	t	f
4329	212	56	AVANCADO	321	t	f
4330	212	58	AVANCADO	321	t	f
4331	212	59	AVANCADO	321	t	f
4332	212	60	AVANCADO	321	t	f
4333	212	61	AVANCADO	321	t	f
4334	212	62	AVANCADO	321	t	f
4335	212	84	INTERMEDIARIO	320	t	f
4336	212	86	BASICO	318	t	f
4337	212	89	AVANCADO	321	t	f
4338	212	94	AVANCADO	321	t	f
4339	212	113	INTERMEDIARIO	320	t	f
4340	212	114	INTERMEDIARIO	320	t	f
4341	212	115	AVANCADO	321	t	f
4342	212	116	AVANCADO	321	t	f
4343	212	117	AVANCADO	321	t	f
4344	212	118	AVANCADO	321	t	f
4345	212	119	BASICO	318	t	f
4346	212	120	BASICO	318	t	f
4347	212	124	BASICO	318	t	f
4348	212	129	INTERMEDIARIO	320	t	f
4349	212	1	INTERMEDIARIO	320	t	f
4350	212	2	BASICO	318	t	f
4351	212	3	BASICO	318	t	f
4352	212	4	AVANCADO	321	t	f
4353	212	5	BASICO	318	t	f
4354	212	6	BASICO	318	t	f
4355	212	7	INTERMEDIARIO	320	t	f
4356	212	8	INTERMEDIARIO	320	t	f
4357	212	9	AVANCADO	321	t	f
4358	212	10	AVANCADO	321	t	f
4359	212	11	BASICO	318	t	f
4360	212	12	AVANCADO	321	t	f
4361	212	63	BASICO	318	t	f
4362	212	64	BASICO	318	t	f
4363	212	65	AVANCADO	321	t	f
4364	212	66	AVANCADO	321	t	f
4365	212	67	BASICO	318	t	f
4366	212	68	BASICO	318	t	f
4367	212	69	BASICO	318	t	f
4368	212	70	BASICO	318	t	f
4369	212	71	BASICO	318	t	f
4370	212	72	AVANCADO	321	t	f
4371	212	73	INTERMEDIARIO	320	t	f
4372	212	74	INTERMEDIARIO	320	t	f
4373	212	75	BASICO	318	t	f
4374	212	76	BASICO	318	t	f
4375	212	77	BASICO	318	t	f
4376	212	78	BASICO	318	t	f
4377	212	79	BASICO	318	t	f
4378	212	81	BASICO	318	t	f
4379	212	82	BASICO	318	t	f
4380	212	108	AVANCADO	321	t	f
4381	212	109	AVANCADO	321	t	f
4382	212	110	BASICO	318	t	f
4383	212	111	AVANCADO	321	t	f
4384	212	112	BASICO	318	t	f
4385	241	98	BASICO	318	t	f
4386	241	99	INTERMEDIARIO	320	t	f
4387	241	100	INTERMEDIARIO	320	t	f
4388	241	101	BASICO	318	t	f
4389	241	102	INTERMEDIARIO	320	t	f
4390	241	103	INTERMEDIARIO	320	t	f
4391	241	104	INTERMEDIARIO	320	t	f
4392	241	105	INTERMEDIARIO	320	t	f
4393	241	106	AVANCADO	321	t	f
4394	241	107	AVANCADO	321	t	f
4395	241	47	BASICO	318	t	f
4396	241	48	INTERMEDIARIO	320	t	f
4397	241	49	AVANCADO	321	t	f
4398	241	50	BASICO	318	t	f
4399	241	51	INTERMEDIARIO	320	t	f
4400	241	52	BASICO	318	t	f
4401	241	28	BASICO	318	t	f
4402	241	29	AVANCADO	321	t	f
4403	241	30	BASICO	318	t	f
4404	241	31	BASICO	318	t	f
4405	241	32	BASICO	318	t	f
4406	241	33	INTERMEDIARIO	320	t	f
4407	241	34	BASICO	318	t	f
4408	241	35	INTERMEDIARIO	320	t	f
4409	241	36	AVANCADO	321	t	f
4410	241	37	INTERMEDIARIO	320	t	f
4411	241	38	INTERMEDIARIO	320	t	f
4412	241	39	AVANCADO	321	t	f
4413	241	40	AVANCADO	321	t	f
4414	241	41	AVANCADO	321	t	f
4415	241	42	INTERMEDIARIO	320	t	f
4416	241	43	AVANCADO	321	t	f
4417	241	44	AVANCADO	321	t	f
4418	241	45	BASICO	318	t	f
4419	241	46	BASICO	318	t	f
4420	241	13	BASICO	318	t	f
4421	241	14	AVANCADO	321	t	f
4422	241	15	BASICO	318	t	f
4423	241	16	INTERMEDIARIO	320	t	f
4424	241	17	INTERMEDIARIO	320	t	f
4425	241	18	BASICO	318	t	f
4426	241	19	BASICO	318	t	f
4427	241	20	INTERMEDIARIO	320	t	f
4428	241	21	AVANCADO	321	t	f
4429	241	22	INTERMEDIARIO	320	t	f
4430	241	23	BASICO	318	t	f
4431	241	24	BASICO	318	t	f
4432	241	25	BASICO	318	t	f
4433	241	26	INTERMEDIARIO	320	t	f
4434	241	27	BASICO	318	t	f
4435	241	53	BASICO	318	t	f
4436	241	54	BASICO	318	t	f
4437	241	55	INTERMEDIARIO	320	t	f
4438	241	56	AVANCADO	321	t	f
4439	241	57	BASICO	318	t	f
4440	241	58	INTERMEDIARIO	320	t	f
4441	241	59	INTERMEDIARIO	320	t	f
4442	241	60	BASICO	318	t	f
4443	241	61	BASICO	318	t	f
4444	241	62	BASICO	318	t	f
4445	241	87	INTERMEDIARIO	320	t	f
4446	241	94	BASICO	318	t	f
4447	241	113	INTERMEDIARIO	320	t	f
4448	241	114	INTERMEDIARIO	320	t	f
4449	241	115	AVANCADO	321	t	f
4450	241	116	AVANCADO	321	t	f
4451	241	117	AVANCADO	321	t	f
4452	241	118	INTERMEDIARIO	320	t	f
4453	241	119	AVANCADO	321	t	f
4454	241	120	INTERMEDIARIO	320	t	f
4455	241	121	INTERMEDIARIO	320	t	f
4456	241	122	BASICO	318	t	f
4457	241	123	BASICO	318	t	f
4458	241	124	INTERMEDIARIO	320	t	f
4459	241	129	AVANCADO	321	t	f
4460	241	1	AVANCADO	321	t	f
4461	241	2	INTERMEDIARIO	320	t	f
4462	241	3	AVANCADO	321	t	f
4463	241	4	AVANCADO	321	t	f
4464	241	5	INTERMEDIARIO	320	t	f
4465	241	8	AVANCADO	321	t	f
4466	241	9	AVANCADO	321	t	f
4467	241	10	AVANCADO	321	t	f
4468	241	11	AVANCADO	321	t	f
4469	241	12	AVANCADO	321	t	f
4470	241	63	BASICO	318	t	f
4471	241	64	BASICO	318	t	f
4472	241	65	AVANCADO	321	t	f
4473	241	66	AVANCADO	321	t	f
4474	241	67	INTERMEDIARIO	320	t	f
4475	241	68	AVANCADO	321	t	f
4476	241	69	BASICO	318	t	f
4477	241	70	INTERMEDIARIO	320	t	f
4478	241	71	BASICO	318	t	f
4479	241	72	AVANCADO	321	t	f
4480	241	73	INTERMEDIARIO	320	t	f
4481	241	74	INTERMEDIARIO	320	t	f
4482	241	75	INTERMEDIARIO	320	t	f
4483	241	79	AVANCADO	321	t	f
4484	241	82	BASICO	318	t	f
4485	241	108	AVANCADO	321	t	f
4486	241	109	AVANCADO	321	t	f
4487	241	111	BASICO	318	t	f
4488	28	98	INTERMEDIARIO	320	t	f
4489	28	99	INTERMEDIARIO	320	t	f
4490	28	100	AVANCADO	321	t	f
4491	28	101	INTERMEDIARIO	320	t	f
4492	28	102	AVANCADO	321	t	f
4493	28	103	AVANCADO	321	t	f
4494	28	104	AVANCADO	321	t	f
4495	28	105	AVANCADO	321	t	f
4496	28	106	AVANCADO	321	t	f
4497	28	107	AVANCADO	321	t	f
4498	28	47	INTERMEDIARIO	320	t	f
4499	28	48	INTERMEDIARIO	320	t	f
4500	28	49	INTERMEDIARIO	320	t	f
4501	28	50	INTERMEDIARIO	320	t	f
4502	28	51	INTERMEDIARIO	320	t	f
4503	28	52	INTERMEDIARIO	320	t	f
4504	28	28	INTERMEDIARIO	320	t	f
4505	28	29	BASICO	318	t	f
4506	28	30	BASICO	318	t	f
4507	28	32	BASICO	318	t	f
4508	28	33	INTERMEDIARIO	320	t	f
4509	28	34	INTERMEDIARIO	320	t	f
4510	28	35	AVANCADO	321	t	f
4511	28	36	AVANCADO	321	t	f
4512	28	37	AVANCADO	321	t	f
4513	28	38	AVANCADO	321	t	f
4514	28	39	AVANCADO	321	t	f
4515	28	40	AVANCADO	321	t	f
4516	28	41	AVANCADO	321	t	f
4517	28	42	BASICO	318	t	f
4518	28	43	BASICO	318	t	f
4519	28	44	INTERMEDIARIO	320	t	f
4520	28	45	BASICO	318	t	f
4521	28	46	BASICO	318	t	f
4522	28	13	INTERMEDIARIO	320	t	f
4523	28	14	INTERMEDIARIO	320	t	f
4524	28	15	INTERMEDIARIO	320	t	f
4525	28	16	INTERMEDIARIO	320	t	f
4526	28	17	INTERMEDIARIO	320	t	f
4527	28	18	INTERMEDIARIO	320	t	f
4528	28	19	INTERMEDIARIO	320	t	f
4529	28	20	INTERMEDIARIO	320	t	f
4530	28	21	INTERMEDIARIO	320	t	f
4531	28	22	INTERMEDIARIO	320	t	f
4532	28	23	INTERMEDIARIO	320	t	f
4533	28	24	INTERMEDIARIO	320	t	f
4534	28	25	INTERMEDIARIO	320	t	f
4535	28	26	INTERMEDIARIO	320	t	f
4536	28	27	INTERMEDIARIO	320	t	f
4537	28	53	INTERMEDIARIO	320	t	f
4538	28	54	INTERMEDIARIO	320	t	f
4539	28	55	INTERMEDIARIO	320	t	f
4540	28	56	INTERMEDIARIO	320	t	f
4541	28	57	INTERMEDIARIO	320	t	f
4542	28	58	INTERMEDIARIO	320	t	f
4543	28	59	INTERMEDIARIO	320	t	f
4544	28	60	INTERMEDIARIO	320	t	f
4545	28	61	INTERMEDIARIO	320	t	f
4546	28	62	INTERMEDIARIO	320	t	f
4547	28	83	BASICO	318	t	f
4548	28	84	BASICO	318	t	f
4549	28	85	BASICO	318	t	f
4550	28	86	BASICO	318	t	f
4551	28	88	BASICO	318	t	f
4552	28	89	INTERMEDIARIO	320	t	f
4553	28	90	INTERMEDIARIO	320	t	f
4554	28	91	INTERMEDIARIO	320	t	f
4555	28	92	INTERMEDIARIO	320	t	f
4556	28	93	INTERMEDIARIO	320	t	f
4557	28	94	INTERMEDIARIO	320	t	f
4558	28	95	INTERMEDIARIO	320	t	f
4559	28	96	INTERMEDIARIO	320	t	f
4560	28	97	INTERMEDIARIO	320	t	f
4561	28	130	INTERMEDIARIO	320	t	f
4562	28	113	BASICO	318	t	f
4563	28	114	BASICO	318	t	f
4564	28	115	BASICO	318	t	f
4565	28	116	BASICO	318	t	f
4566	28	117	BASICO	318	t	f
4567	28	118	BASICO	318	t	f
4568	28	119	BASICO	318	t	f
4569	28	120	BASICO	318	t	f
4570	28	121	BASICO	318	t	f
4571	28	122	BASICO	318	t	f
4572	28	123	BASICO	318	t	f
4573	28	124	BASICO	318	t	f
4574	28	125	BASICO	318	t	f
4575	28	126	BASICO	318	t	f
4576	28	127	BASICO	318	t	f
4577	28	129	BASICO	318	t	f
4578	28	1	AVANCADO	321	t	f
4579	28	2	INTERMEDIARIO	320	t	f
4580	28	3	INTERMEDIARIO	320	t	f
4581	28	4	INTERMEDIARIO	320	t	f
4582	28	5	INTERMEDIARIO	320	t	f
4583	28	6	INTERMEDIARIO	320	t	f
4584	28	7	INTERMEDIARIO	320	t	f
4585	28	8	INTERMEDIARIO	320	t	f
4586	28	9	INTERMEDIARIO	320	t	f
4587	28	10	AVANCADO	321	t	f
4588	28	11	AVANCADO	321	t	f
4589	28	12	AVANCADO	321	t	f
4590	28	63	INTERMEDIARIO	320	t	f
4591	28	64	BASICO	318	t	f
4592	28	65	BASICO	318	t	f
4593	28	66	BASICO	318	t	f
4594	28	67	BASICO	318	t	f
4595	28	68	INTERMEDIARIO	320	t	f
4596	28	69	INTERMEDIARIO	320	t	f
4597	28	70	BASICO	318	t	f
4598	28	71	BASICO	318	t	f
4599	28	72	BASICO	318	t	f
4600	28	73	BASICO	318	t	f
4601	28	74	BASICO	318	t	f
4602	28	75	BASICO	318	t	f
4603	28	76	BASICO	318	t	f
4604	28	77	BASICO	318	t	f
4605	28	78	BASICO	318	t	f
4606	28	79	INTERMEDIARIO	320	t	f
4607	28	81	BASICO	318	t	f
4608	28	82	BASICO	318	t	f
4609	28	108	BASICO	318	t	f
4610	28	109	BASICO	318	t	f
4611	28	110	BASICO	318	t	f
4612	28	111	BASICO	318	t	f
4613	28	112	BASICO	318	t	f
4614	75	103	BASICO	318	t	f
4615	75	106	BASICO	318	t	f
4616	290	102	BASICO	318	t	f
4617	290	103	INTERMEDIARIO	320	t	f
4618	290	104	BASICO	318	t	f
4619	290	105	BASICO	318	t	f
4620	290	106	INTERMEDIARIO	320	t	f
4621	290	107	BASICO	318	t	f
4622	290	50	AVANCADO	321	t	f
4623	290	51	BASICO	318	t	f
4624	290	29	AVANCADO	321	t	f
4625	290	35	BASICO	318	t	f
4626	290	36	INTERMEDIARIO	320	t	f
4627	290	38	AVANCADO	321	t	f
4628	290	41	BASICO	318	t	f
4629	290	43	BASICO	318	t	f
4630	290	44	BASICO	318	t	f
4631	290	45	BASICO	318	t	f
4632	290	13	BASICO	318	t	f
4633	290	14	BASICO	318	t	f
4634	290	16	BASICO	318	t	f
4635	290	18	BASICO	318	t	f
4636	290	19	BASICO	318	t	f
4637	290	20	AVANCADO	321	t	f
4638	290	21	AVANCADO	321	t	f
4639	290	25	BASICO	318	t	f
4640	290	53	BASICO	318	t	f
4641	290	55	AVANCADO	321	t	f
4642	290	56	AVANCADO	321	t	f
4643	290	58	BASICO	318	t	f
4644	290	59	BASICO	318	t	f
4645	290	61	BASICO	318	t	f
4646	290	83	BASICO	318	t	f
4647	290	84	BASICO	318	t	f
4648	290	86	BASICO	318	t	f
4649	290	115	INTERMEDIARIO	320	t	f
4650	290	116	BASICO	318	t	f
4651	290	117	AVANCADO	321	t	f
4652	290	119	AVANCADO	321	t	f
4653	290	2	BASICO	318	t	f
4654	290	7	BASICO	318	t	f
4655	290	8	BASICO	318	t	f
4656	290	9	BASICO	318	t	f
4657	290	10	BASICO	318	t	f
4658	290	63	BASICO	318	t	f
4659	290	64	BASICO	318	t	f
4660	290	65	BASICO	318	t	f
4661	290	66	BASICO	318	t	f
4662	290	67	BASICO	318	t	f
4663	290	68	BASICO	318	t	f
4664	290	69	BASICO	318	t	f
4665	290	70	BASICO	318	t	f
4666	290	72	AVANCADO	321	t	f
4667	290	73	BASICO	318	t	f
4668	290	74	BASICO	318	t	f
4669	290	75	BASICO	318	t	f
4670	290	76	BASICO	318	t	f
4671	290	77	BASICO	318	t	f
4672	290	79	BASICO	318	t	f
4673	290	81	AVANCADO	321	t	f
4674	290	82	AVANCADO	321	t	f
4675	290	108	INTERMEDIARIO	320	t	f
4676	290	109	BASICO	318	t	f
4677	290	110	BASICO	318	t	f
4678	290	111	INTERMEDIARIO	320	t	f
4679	290	112	INTERMEDIARIO	320	t	f
4680	30	98	AVANCADO	321	t	f
4681	30	99	BASICO	318	t	f
4682	30	100	BASICO	318	t	f
4683	30	101	BASICO	318	t	f
4684	30	102	BASICO	318	t	f
4685	30	103	INTERMEDIARIO	320	t	f
4686	30	104	AVANCADO	321	t	f
4687	30	105	INTERMEDIARIO	320	t	f
4688	30	106	AVANCADO	321	t	f
4689	30	107	INTERMEDIARIO	320	t	f
4690	30	47	BASICO	318	t	f
4691	30	48	BASICO	318	t	f
4692	30	49	BASICO	318	t	f
4693	30	50	INTERMEDIARIO	320	t	f
4694	30	51	INTERMEDIARIO	320	t	f
4695	30	52	BASICO	318	t	f
4696	30	28	BASICO	318	t	f
4697	30	29	BASICO	318	t	f
4698	30	30	BASICO	318	t	f
4699	30	31	BASICO	318	t	f
4700	30	32	BASICO	318	t	f
4701	30	33	BASICO	318	t	f
4702	30	34	BASICO	318	t	f
4703	30	35	BASICO	318	t	f
4704	30	36	BASICO	318	t	f
4705	30	37	BASICO	318	t	f
4706	30	38	BASICO	318	t	f
4707	30	39	BASICO	318	t	f
4708	30	40	BASICO	318	t	f
4709	30	41	BASICO	318	t	f
4710	30	42	BASICO	318	t	f
4711	30	43	BASICO	318	t	f
4712	30	44	BASICO	318	t	f
4713	30	45	BASICO	318	t	f
4714	30	46	BASICO	318	t	f
4715	30	13	BASICO	318	t	f
4716	30	14	BASICO	318	t	f
4717	30	15	BASICO	318	t	f
4718	30	16	BASICO	318	t	f
4719	30	17	BASICO	318	t	f
4720	30	18	BASICO	318	t	f
4721	30	19	BASICO	318	t	f
4722	30	20	BASICO	318	t	f
4723	30	21	BASICO	318	t	f
4724	30	22	BASICO	318	t	f
4725	30	23	BASICO	318	t	f
4726	30	24	BASICO	318	t	f
4727	30	25	BASICO	318	t	f
4728	30	26	BASICO	318	t	f
4729	30	27	BASICO	318	t	f
4730	30	53	BASICO	318	t	f
4731	30	54	BASICO	318	t	f
4732	30	55	BASICO	318	t	f
4733	30	56	BASICO	318	t	f
4734	30	57	BASICO	318	t	f
4735	30	58	BASICO	318	t	f
4736	30	59	BASICO	318	t	f
4737	30	60	BASICO	318	t	f
4738	30	61	BASICO	318	t	f
4739	30	62	BASICO	318	t	f
4740	30	83	BASICO	318	t	f
4741	30	84	BASICO	318	t	f
4742	30	85	BASICO	318	t	f
4743	30	86	BASICO	318	t	f
4744	30	87	INTERMEDIARIO	320	t	f
4745	30	88	BASICO	318	t	f
4746	30	89	BASICO	318	t	f
4747	30	90	BASICO	318	t	f
4748	30	91	INTERMEDIARIO	320	t	f
4749	30	92	INTERMEDIARIO	320	t	f
4750	30	93	BASICO	318	t	f
4751	30	94	INTERMEDIARIO	320	t	f
4752	30	95	BASICO	318	t	f
4753	30	96	AVANCADO	321	t	f
4754	30	97	BASICO	318	t	f
4755	30	130	INTERMEDIARIO	320	t	f
4756	30	113	BASICO	318	t	f
4757	30	114	BASICO	318	t	f
4758	30	115	BASICO	318	t	f
4759	30	116	BASICO	318	t	f
4760	30	117	BASICO	318	t	f
4761	30	118	BASICO	318	t	f
4762	30	119	BASICO	318	t	f
4763	30	120	BASICO	318	t	f
4764	30	121	BASICO	318	t	f
4765	30	122	BASICO	318	t	f
4766	30	123	BASICO	318	t	f
4767	30	124	BASICO	318	t	f
4768	30	125	BASICO	318	t	f
4769	30	126	BASICO	318	t	f
4770	30	127	BASICO	318	t	f
4771	30	129	BASICO	318	t	f
4772	30	1	BASICO	318	t	f
4773	30	2	BASICO	318	t	f
4774	30	3	BASICO	318	t	f
4775	30	4	BASICO	318	t	f
4776	30	5	BASICO	318	t	f
4777	30	6	BASICO	318	t	f
4778	30	7	BASICO	318	t	f
4779	30	8	BASICO	318	t	f
4780	30	9	BASICO	318	t	f
4781	30	10	BASICO	318	t	f
4782	30	11	BASICO	318	t	f
4783	30	12	BASICO	318	t	f
4784	30	63	BASICO	318	t	f
4785	30	64	BASICO	318	t	f
4786	30	65	BASICO	318	t	f
4787	30	66	BASICO	318	t	f
4788	30	67	BASICO	318	t	f
4789	30	68	BASICO	318	t	f
4790	30	69	BASICO	318	t	f
4791	30	70	BASICO	318	t	f
4792	30	71	BASICO	318	t	f
4793	30	72	BASICO	318	t	f
4794	30	73	BASICO	318	t	f
4795	30	74	BASICO	318	t	f
4796	30	75	BASICO	318	t	f
4797	30	76	BASICO	318	t	f
4798	30	77	BASICO	318	t	f
4799	30	78	BASICO	318	t	f
4800	30	79	BASICO	318	t	f
4801	30	81	BASICO	318	t	f
4802	30	82	BASICO	318	t	f
4803	30	108	BASICO	318	t	f
4804	30	109	BASICO	318	t	f
4805	30	110	BASICO	318	t	f
4806	30	111	BASICO	318	t	f
4807	30	112	BASICO	318	t	f
4808	20	98	INTERMEDIARIO	320	t	f
4809	20	99	BASICO	318	t	f
4810	20	100	BASICO	318	t	f
4811	20	101	BASICO	318	t	f
4812	20	102	BASICO	318	t	f
4813	20	103	BASICO	318	t	f
4814	20	104	BASICO	318	t	f
4815	20	105	BASICO	318	t	f
4816	20	106	INTERMEDIARIO	320	t	f
4817	20	107	INTERMEDIARIO	320	t	f
4818	20	47	BASICO	318	t	f
4819	20	48	BASICO	318	t	f
4820	20	49	INTERMEDIARIO	320	t	f
4821	20	50	BASICO	318	t	f
4822	20	51	BASICO	318	t	f
4823	20	52	BASICO	318	t	f
4824	20	28	INTERMEDIARIO	320	t	f
4825	20	29	AVANCADO	321	t	f
4826	20	30	BASICO	318	t	f
4827	20	31	BASICO	318	t	f
4828	20	32	BASICO	318	t	f
4829	20	33	INTERMEDIARIO	320	t	f
4830	20	34	BASICO	318	t	f
4831	20	35	BASICO	318	t	f
4832	20	36	INTERMEDIARIO	320	t	f
4833	20	37	BASICO	318	t	f
4834	20	38	INTERMEDIARIO	320	t	f
4835	20	39	BASICO	318	t	f
4836	20	40	INTERMEDIARIO	320	t	f
4837	20	41	INTERMEDIARIO	320	t	f
4838	20	42	BASICO	318	t	f
4839	20	43	BASICO	318	t	f
4840	20	44	INTERMEDIARIO	320	t	f
4841	20	45	BASICO	318	t	f
4842	20	46	BASICO	318	t	f
4843	20	13	BASICO	318	t	f
4844	20	14	BASICO	318	t	f
4845	20	15	INTERMEDIARIO	320	t	f
4846	20	16	AVANCADO	321	t	f
4847	20	17	BASICO	318	t	f
4848	20	18	BASICO	318	t	f
4849	20	19	INTERMEDIARIO	320	t	f
4850	20	20	BASICO	318	t	f
4851	20	21	BASICO	318	t	f
4852	20	22	BASICO	318	t	f
4853	20	23	AVANCADO	321	t	f
4854	20	24	BASICO	318	t	f
4855	20	25	BASICO	318	t	f
4856	20	26	AVANCADO	321	t	f
4857	20	27	BASICO	318	t	f
4858	20	54	BASICO	318	t	f
4859	20	55	BASICO	318	t	f
4860	20	56	BASICO	318	t	f
4861	20	57	BASICO	318	t	f
4862	20	58	BASICO	318	t	f
4863	20	59	BASICO	318	t	f
4864	20	60	BASICO	318	t	f
4865	20	61	BASICO	318	t	f
4866	20	62	BASICO	318	t	f
4867	20	83	BASICO	318	t	f
4868	20	84	BASICO	318	t	f
4869	20	85	BASICO	318	t	f
4870	20	86	BASICO	318	t	f
4871	20	87	BASICO	318	t	f
4872	20	88	BASICO	318	t	f
4873	20	89	BASICO	318	t	f
4874	20	90	BASICO	318	t	f
4875	20	91	BASICO	318	t	f
4876	20	92	BASICO	318	t	f
4877	20	93	BASICO	318	t	f
4878	20	94	BASICO	318	t	f
4879	20	95	BASICO	318	t	f
4880	20	96	BASICO	318	t	f
4881	20	97	BASICO	318	t	f
4882	20	130	BASICO	318	t	f
4883	20	113	BASICO	318	t	f
4884	20	114	INTERMEDIARIO	320	t	f
4885	20	115	INTERMEDIARIO	320	t	f
4886	20	116	INTERMEDIARIO	320	t	f
4887	20	117	INTERMEDIARIO	320	t	f
4888	20	118	INTERMEDIARIO	320	t	f
4889	20	119	INTERMEDIARIO	320	t	f
4890	20	120	BASICO	318	t	f
4891	20	121	BASICO	318	t	f
4892	20	122	BASICO	318	t	f
4893	20	123	BASICO	318	t	f
4894	20	124	BASICO	318	t	f
4895	20	125	BASICO	318	t	f
4896	20	126	BASICO	318	t	f
4897	20	127	BASICO	318	t	f
4898	20	129	INTERMEDIARIO	320	t	f
4899	20	1	INTERMEDIARIO	320	t	f
4900	20	2	BASICO	318	t	f
4901	20	4	AVANCADO	321	t	f
4902	20	5	INTERMEDIARIO	320	t	f
4903	20	6	BASICO	318	t	f
4904	20	7	BASICO	318	t	f
4905	20	8	INTERMEDIARIO	320	t	f
4906	20	9	INTERMEDIARIO	320	t	f
4907	20	10	BASICO	318	t	f
4908	20	11	INTERMEDIARIO	320	t	f
4909	20	12	INTERMEDIARIO	320	t	f
4910	20	63	BASICO	318	t	f
4911	20	64	BASICO	318	t	f
4912	20	65	INTERMEDIARIO	320	t	f
4913	20	66	INTERMEDIARIO	320	t	f
4914	20	67	BASICO	318	t	f
4915	20	68	BASICO	318	t	f
4916	20	69	BASICO	318	t	f
4917	20	70	BASICO	318	t	f
4918	20	71	BASICO	318	t	f
4919	20	72	BASICO	318	t	f
4920	20	73	BASICO	318	t	f
4921	20	74	BASICO	318	t	f
4922	20	75	BASICO	318	t	f
4923	20	76	BASICO	318	t	f
4924	20	77	BASICO	318	t	f
4925	20	78	BASICO	318	t	f
4926	20	79	BASICO	318	t	f
4927	20	81	BASICO	318	t	f
4928	20	82	BASICO	318	t	f
4929	20	108	INTERMEDIARIO	320	t	f
4930	20	109	INTERMEDIARIO	320	t	f
4931	20	110	INTERMEDIARIO	320	t	f
4932	20	111	AVANCADO	321	t	f
4933	20	112	BASICO	318	t	f
4934	15	102	AVANCADO	321	t	f
4935	15	106	AVANCADO	321	t	f
4936	15	107	AVANCADO	321	t	f
4937	15	49	AVANCADO	321	t	f
4938	15	50	AVANCADO	321	t	f
4939	15	52	AVANCADO	321	t	f
4940	15	28	AVANCADO	321	t	f
4941	15	29	AVANCADO	321	t	f
4942	15	30	AVANCADO	321	t	f
4943	15	33	AVANCADO	321	t	f
4944	15	34	AVANCADO	321	t	f
4945	15	36	AVANCADO	321	t	f
4946	15	37	AVANCADO	321	t	f
4947	15	38	AVANCADO	321	t	f
4948	15	40	AVANCADO	321	t	f
4949	15	41	AVANCADO	321	t	f
4950	15	42	AVANCADO	321	t	f
4951	15	43	AVANCADO	321	t	f
4952	15	44	AVANCADO	321	t	f
4953	15	45	AVANCADO	321	t	f
4954	15	46	INTERMEDIARIO	320	t	f
4955	15	13	AVANCADO	321	t	f
4956	15	14	AVANCADO	321	t	f
4957	15	15	AVANCADO	321	t	f
4958	15	16	AVANCADO	321	t	f
4959	15	17	AVANCADO	321	t	f
4960	15	18	AVANCADO	321	t	f
4961	15	19	AVANCADO	321	t	f
4962	15	20	AVANCADO	321	t	f
4963	15	21	AVANCADO	321	t	f
4964	15	22	BASICO	318	t	f
4965	15	23	AVANCADO	321	t	f
4966	15	24	INTERMEDIARIO	320	t	f
4967	15	25	INTERMEDIARIO	320	t	f
4968	15	26	AVANCADO	321	t	f
4969	15	27	AVANCADO	321	t	f
4970	15	53	AVANCADO	321	t	f
4971	15	54	AVANCADO	321	t	f
4972	15	55	AVANCADO	321	t	f
4973	15	56	AVANCADO	321	t	f
4974	15	57	AVANCADO	321	t	f
4975	15	58	AVANCADO	321	t	f
4976	15	59	AVANCADO	321	t	f
4977	15	60	AVANCADO	321	t	f
4978	15	61	AVANCADO	321	t	f
4979	15	62	AVANCADO	321	t	f
4980	15	83	BASICO	318	t	f
4981	15	84	AVANCADO	321	t	f
4982	15	85	AVANCADO	321	t	f
4983	15	86	AVANCADO	321	t	f
4984	15	87	AVANCADO	321	t	f
4985	15	88	INTERMEDIARIO	320	t	f
4986	15	89	BASICO	318	t	f
4987	15	90	AVANCADO	321	t	f
4988	15	91	BASICO	318	t	f
4989	15	92	BASICO	318	t	f
4990	15	93	BASICO	318	t	f
4991	15	94	AVANCADO	321	t	f
4992	15	95	BASICO	318	t	f
4993	15	96	INTERMEDIARIO	320	t	f
4994	15	97	BASICO	318	t	f
4995	15	130	BASICO	318	t	f
4996	15	113	AVANCADO	321	t	f
4997	15	114	AVANCADO	321	t	f
4998	15	115	AVANCADO	321	t	f
4999	15	116	AVANCADO	321	t	f
5000	15	117	AVANCADO	321	t	f
5001	15	118	AVANCADO	321	t	f
5002	15	119	AVANCADO	321	t	f
5003	15	120	AVANCADO	321	t	f
5004	15	121	BASICO	318	t	f
5005	15	122	AVANCADO	321	t	f
5006	15	123	AVANCADO	321	t	f
5007	15	124	AVANCADO	321	t	f
5008	15	125	AVANCADO	321	t	f
5009	15	126	INTERMEDIARIO	320	t	f
5010	15	127	AVANCADO	321	t	f
5011	15	129	AVANCADO	321	t	f
5012	15	1	AVANCADO	321	t	f
5013	15	2	AVANCADO	321	t	f
5014	15	3	INTERMEDIARIO	320	t	f
5015	15	4	AVANCADO	321	t	f
5016	15	5	AVANCADO	321	t	f
5017	15	6	BASICO	318	t	f
5018	15	7	AVANCADO	321	t	f
5019	15	8	AVANCADO	321	t	f
5020	15	9	AVANCADO	321	t	f
5021	15	10	AVANCADO	321	t	f
5022	15	11	AVANCADO	321	t	f
5023	15	12	AVANCADO	321	t	f
5024	15	63	INTERMEDIARIO	320	t	f
5025	15	64	INTERMEDIARIO	320	t	f
5026	15	65	AVANCADO	321	t	f
5027	15	66	AVANCADO	321	t	f
5028	15	67	AVANCADO	321	t	f
5029	15	68	INTERMEDIARIO	320	t	f
5030	15	69	INTERMEDIARIO	320	t	f
5031	15	70	BASICO	318	t	f
5032	15	71	INTERMEDIARIO	320	t	f
5033	15	72	AVANCADO	321	t	f
5034	15	73	INTERMEDIARIO	320	t	f
5035	15	74	AVANCADO	321	t	f
5036	15	75	AVANCADO	321	t	f
5037	15	76	AVANCADO	321	t	f
5038	15	77	BASICO	318	t	f
5039	15	78	INTERMEDIARIO	320	t	f
5040	15	79	BASICO	318	t	f
5041	15	81	BASICO	318	t	f
5042	15	82	AVANCADO	321	t	f
5043	15	108	AVANCADO	321	t	f
5044	15	109	AVANCADO	321	t	f
5045	15	110	AVANCADO	321	t	f
5046	15	111	AVANCADO	321	t	f
5047	15	112	AVANCADO	321	t	f
5048	129	99	AVANCADO	321	t	f
5049	129	103	BASICO	318	t	f
5050	129	104	AVANCADO	321	t	f
5051	129	107	AVANCADO	321	t	f
5052	129	48	INTERMEDIARIO	320	t	f
5053	129	49	INTERMEDIARIO	320	t	f
5054	129	51	AVANCADO	321	t	f
5055	129	29	INTERMEDIARIO	320	t	f
5056	129	37	INTERMEDIARIO	320	t	f
5057	129	39	AVANCADO	321	t	f
5058	129	43	INTERMEDIARIO	320	t	f
5059	129	44	BASICO	318	t	f
5060	129	13	INTERMEDIARIO	320	t	f
5061	129	14	AVANCADO	321	t	f
5062	129	15	INTERMEDIARIO	320	t	f
5063	129	17	BASICO	318	t	f
5064	129	21	AVANCADO	321	t	f
5065	129	22	AVANCADO	321	t	f
5066	129	27	AVANCADO	321	t	f
5067	129	58	AVANCADO	321	t	f
5068	129	94	INTERMEDIARIO	320	t	f
5069	129	115	AVANCADO	321	t	f
5070	129	116	INTERMEDIARIO	320	t	f
5071	129	117	AVANCADO	321	t	f
5072	129	118	BASICO	318	t	f
5073	129	122	BASICO	318	t	f
5074	129	123	BASICO	318	t	f
5075	129	124	INTERMEDIARIO	320	t	f
5076	129	126	BASICO	318	t	f
5077	129	129	INTERMEDIARIO	320	t	f
5078	129	1	AVANCADO	321	t	f
5079	129	3	AVANCADO	321	t	f
5080	129	8	INTERMEDIARIO	320	t	f
5081	129	10	AVANCADO	321	t	f
5082	129	12	AVANCADO	321	t	f
5083	129	66	INTERMEDIARIO	320	t	f
5084	129	67	INTERMEDIARIO	320	t	f
5085	129	72	INTERMEDIARIO	320	t	f
5086	129	82	INTERMEDIARIO	320	t	f
5087	17	102	BASICO	318	t	f
5088	17	105	INTERMEDIARIO	320	t	f
5089	17	106	INTERMEDIARIO	320	t	f
5090	17	107	INTERMEDIARIO	320	t	f
5091	17	47	BASICO	318	t	f
5092	17	50	BASICO	318	t	f
5093	17	29	AVANCADO	321	t	f
5094	17	33	BASICO	318	t	f
5095	17	34	BASICO	318	t	f
5096	17	35	INTERMEDIARIO	320	t	f
5097	17	36	INTERMEDIARIO	320	t	f
5098	17	38	INTERMEDIARIO	320	t	f
5099	17	40	INTERMEDIARIO	320	t	f
5100	17	41	INTERMEDIARIO	320	t	f
5101	17	43	INTERMEDIARIO	320	t	f
5102	17	44	INTERMEDIARIO	320	t	f
5103	17	13	BASICO	318	t	f
5104	17	15	INTERMEDIARIO	320	t	f
5105	17	18	INTERMEDIARIO	320	t	f
5106	17	19	INTERMEDIARIO	320	t	f
5107	17	20	INTERMEDIARIO	320	t	f
5108	17	21	BASICO	318	t	f
5109	17	54	AVANCADO	321	t	f
5110	17	55	AVANCADO	321	t	f
5111	17	56	AVANCADO	321	t	f
5112	17	57	BASICO	318	t	f
5113	17	58	AVANCADO	321	t	f
5114	17	59	INTERMEDIARIO	320	t	f
5115	17	60	INTERMEDIARIO	320	t	f
5116	17	61	INTERMEDIARIO	320	t	f
5117	17	62	BASICO	318	t	f
5118	17	86	BASICO	318	t	f
5119	17	114	BASICO	318	t	f
5120	17	115	INTERMEDIARIO	320	t	f
5121	17	116	INTERMEDIARIO	320	t	f
5122	17	117	INTERMEDIARIO	320	t	f
5123	17	119	INTERMEDIARIO	320	t	f
5124	17	120	BASICO	318	t	f
5125	17	122	BASICO	318	t	f
5126	17	124	INTERMEDIARIO	320	t	f
5127	17	129	INTERMEDIARIO	320	t	f
5128	17	1	BASICO	318	t	f
5129	17	2	BASICO	318	t	f
5130	17	7	INTERMEDIARIO	320	t	f
5131	17	8	INTERMEDIARIO	320	t	f
5132	17	9	AVANCADO	321	t	f
5133	17	12	INTERMEDIARIO	320	t	f
5134	17	63	BASICO	318	t	f
5135	17	64	BASICO	318	t	f
5136	17	65	INTERMEDIARIO	320	t	f
5137	17	66	INTERMEDIARIO	320	t	f
5138	17	110	INTERMEDIARIO	320	t	f
5139	110	98	BASICO	318	t	f
5140	110	99	BASICO	318	t	f
5141	110	100	BASICO	318	t	f
5142	110	101	BASICO	318	t	f
5143	110	102	BASICO	318	t	f
5144	110	103	BASICO	318	t	f
5145	110	106	BASICO	318	t	f
5146	110	107	BASICO	318	t	f
5147	110	48	BASICO	318	t	f
5148	110	49	BASICO	318	t	f
5149	110	50	BASICO	318	t	f
5150	110	41	BASICO	318	t	f
5151	110	21	BASICO	318	t	f
5152	110	55	BASICO	318	t	f
5153	110	56	BASICO	318	t	f
5154	110	58	BASICO	318	t	f
5155	110	84	BASICO	318	t	f
5156	110	92	BASICO	318	t	f
5157	110	130	BASICO	318	t	f
5158	110	117	BASICO	318	t	f
5159	110	119	BASICO	318	t	f
5160	110	2	BASICO	318	t	f
5161	110	12	BASICO	318	t	f
5162	110	63	BASICO	318	t	f
5163	110	64	BASICO	318	t	f
5164	322	72	BASICO	318	t	f
5165	318	98	AVANCADO	321	t	f
5166	318	99	AVANCADO	321	t	f
5167	318	100	INTERMEDIARIO	320	t	f
5168	318	101	INTERMEDIARIO	320	t	f
5169	318	102	AVANCADO	321	t	f
5170	318	103	AVANCADO	321	t	f
5171	318	104	INTERMEDIARIO	320	t	f
5172	318	105	AVANCADO	321	t	f
5173	318	106	AVANCADO	321	t	f
5174	318	107	AVANCADO	321	t	f
5175	318	47	AVANCADO	321	t	f
5176	318	48	AVANCADO	321	t	f
5177	318	49	INTERMEDIARIO	320	t	f
5178	318	50	AVANCADO	321	t	f
5179	318	51	INTERMEDIARIO	320	t	f
5180	318	52	AVANCADO	321	t	f
5181	318	28	AVANCADO	321	t	f
5182	318	29	AVANCADO	321	t	f
5183	318	30	AVANCADO	321	t	f
5184	318	31	AVANCADO	321	t	f
5185	318	32	AVANCADO	321	t	f
5186	318	33	AVANCADO	321	t	f
5187	318	34	AVANCADO	321	t	f
5188	318	35	AVANCADO	321	t	f
5189	318	36	AVANCADO	321	t	f
5190	318	37	AVANCADO	321	t	f
5191	318	38	AVANCADO	321	t	f
5192	318	39	AVANCADO	321	t	f
5193	318	40	AVANCADO	321	t	f
5194	318	41	AVANCADO	321	t	f
5195	318	42	AVANCADO	321	t	f
5196	318	43	AVANCADO	321	t	f
5197	318	44	AVANCADO	321	t	f
5198	318	45	AVANCADO	321	t	f
5199	318	46	AVANCADO	321	t	f
5200	318	13	AVANCADO	321	t	f
5201	318	14	AVANCADO	321	t	f
5202	318	15	AVANCADO	321	t	f
5203	318	16	AVANCADO	321	t	f
5204	318	17	AVANCADO	321	t	f
5205	318	18	AVANCADO	321	t	f
5206	318	19	AVANCADO	321	t	f
5207	318	20	AVANCADO	321	t	f
5208	318	21	AVANCADO	321	t	f
5209	318	22	AVANCADO	321	t	f
5210	318	23	INTERMEDIARIO	320	t	f
5211	318	24	INTERMEDIARIO	320	t	f
5212	318	25	INTERMEDIARIO	320	t	f
5213	318	26	AVANCADO	321	t	f
5214	318	27	AVANCADO	321	t	f
5215	318	53	AVANCADO	321	t	f
5216	318	54	AVANCADO	321	t	f
5217	318	55	AVANCADO	321	t	f
5218	318	56	AVANCADO	321	t	f
5219	318	57	INTERMEDIARIO	320	t	f
5220	318	58	AVANCADO	321	t	f
5221	318	59	AVANCADO	321	t	f
5222	318	60	AVANCADO	321	t	f
5223	318	61	AVANCADO	321	t	f
5224	318	62	AVANCADO	321	t	f
5225	318	83	AVANCADO	321	t	f
5226	318	84	AVANCADO	321	t	f
5227	318	85	AVANCADO	321	t	f
5228	318	86	AVANCADO	321	t	f
5229	318	87	AVANCADO	321	t	f
5230	318	88	AVANCADO	321	t	f
5231	318	89	AVANCADO	321	t	f
5232	318	90	AVANCADO	321	t	f
5233	318	91	AVANCADO	321	t	f
5234	318	92	AVANCADO	321	t	f
5235	318	93	AVANCADO	321	t	f
5236	318	94	AVANCADO	321	t	f
5237	318	95	AVANCADO	321	t	f
5238	318	96	AVANCADO	321	t	f
5239	318	97	AVANCADO	321	t	f
5240	318	130	INTERMEDIARIO	320	t	f
5241	318	113	AVANCADO	321	t	f
5242	318	114	AVANCADO	321	t	f
5243	318	115	AVANCADO	321	t	f
5244	318	116	AVANCADO	321	t	f
5245	318	117	AVANCADO	321	t	f
5246	318	118	AVANCADO	321	t	f
5247	318	119	AVANCADO	321	t	f
5248	318	120	AVANCADO	321	t	f
5249	318	121	AVANCADO	321	t	f
5250	318	122	AVANCADO	321	t	f
5251	318	123	AVANCADO	321	t	f
5252	318	124	AVANCADO	321	t	f
5253	318	125	AVANCADO	321	t	f
5254	318	126	AVANCADO	321	t	f
5255	318	127	AVANCADO	321	t	f
5256	318	129	AVANCADO	321	t	f
5257	318	1	AVANCADO	321	t	f
5258	318	2	AVANCADO	321	t	f
5259	318	3	AVANCADO	321	t	f
5260	318	4	AVANCADO	321	t	f
5261	318	5	AVANCADO	321	t	f
5262	318	6	AVANCADO	321	t	f
5263	318	7	AVANCADO	321	t	f
5264	318	8	AVANCADO	321	t	f
5265	318	9	AVANCADO	321	t	f
5266	318	10	AVANCADO	321	t	f
5267	318	11	AVANCADO	321	t	f
5268	318	12	AVANCADO	321	t	f
5269	318	63	AVANCADO	321	t	f
5270	318	64	AVANCADO	321	t	f
5271	318	65	AVANCADO	321	t	f
5272	318	66	AVANCADO	321	t	f
5273	318	67	AVANCADO	321	t	f
5274	318	68	AVANCADO	321	t	f
5275	318	69	AVANCADO	321	t	f
5276	318	70	AVANCADO	321	t	f
5277	318	71	AVANCADO	321	t	f
5278	318	72	AVANCADO	321	t	f
5279	318	73	AVANCADO	321	t	f
5280	318	74	AVANCADO	321	t	f
5281	318	75	AVANCADO	321	t	f
5282	318	76	AVANCADO	321	t	f
5283	318	77	AVANCADO	321	t	f
5284	318	78	AVANCADO	321	t	f
5285	318	79	AVANCADO	321	t	f
5286	318	81	AVANCADO	321	t	f
5287	318	82	AVANCADO	321	t	f
5288	318	108	AVANCADO	321	t	f
5289	318	109	AVANCADO	321	t	f
5290	318	110	AVANCADO	321	t	f
5291	318	111	AVANCADO	321	t	f
5292	318	112	AVANCADO	321	t	f
5293	320	98	BASICO	318	t	f
5294	320	99	BASICO	318	t	f
5295	320	100	BASICO	318	t	f
5296	320	101	BASICO	318	t	f
5297	320	102	BASICO	318	t	f
5298	320	103	BASICO	318	t	f
5299	320	104	BASICO	318	t	f
5300	320	105	BASICO	318	t	f
5301	320	106	BASICO	318	t	f
5302	320	107	BASICO	318	t	f
5303	320	47	BASICO	318	t	f
5304	320	48	BASICO	318	t	f
5305	320	49	INTERMEDIARIO	320	t	f
5306	320	50	INTERMEDIARIO	320	t	f
5307	320	51	BASICO	318	t	f
5308	320	52	INTERMEDIARIO	320	t	f
5309	320	28	BASICO	318	t	f
5310	320	29	BASICO	318	t	f
5311	320	30	BASICO	318	t	f
5312	320	31	BASICO	318	t	f
5313	320	32	BASICO	318	t	f
5314	320	33	BASICO	318	t	f
5315	320	34	BASICO	318	t	f
5316	320	35	INTERMEDIARIO	320	t	f
5317	320	36	INTERMEDIARIO	320	t	f
5318	320	37	BASICO	318	t	f
5319	320	38	BASICO	318	t	f
5320	320	39	BASICO	318	t	f
5321	320	40	BASICO	318	t	f
5322	320	41	BASICO	318	t	f
5323	320	42	BASICO	318	t	f
5324	320	43	INTERMEDIARIO	320	t	f
5325	320	45	BASICO	318	t	f
5326	320	46	BASICO	318	t	f
5327	320	13	BASICO	318	t	f
5328	320	14	BASICO	318	t	f
5329	320	15	BASICO	318	t	f
5330	320	16	BASICO	318	t	f
5331	320	17	BASICO	318	t	f
5332	320	18	BASICO	318	t	f
5333	320	19	BASICO	318	t	f
5334	320	20	BASICO	318	t	f
5335	320	21	INTERMEDIARIO	320	t	f
5336	320	22	BASICO	318	t	f
5337	320	23	BASICO	318	t	f
5338	320	24	BASICO	318	t	f
5339	320	25	BASICO	318	t	f
5340	320	26	BASICO	318	t	f
5341	320	27	BASICO	318	t	f
5342	320	53	BASICO	318	t	f
5343	320	54	BASICO	318	t	f
5344	320	55	AVANCADO	321	t	f
5345	320	56	AVANCADO	321	t	f
5346	320	57	BASICO	318	t	f
5347	320	58	INTERMEDIARIO	320	t	f
5348	320	59	INTERMEDIARIO	320	t	f
5349	320	60	BASICO	318	t	f
5350	320	61	INTERMEDIARIO	320	t	f
5351	320	62	BASICO	318	t	f
5352	320	83	BASICO	318	t	f
5353	320	84	BASICO	318	t	f
5354	320	85	BASICO	318	t	f
5355	320	86	BASICO	318	t	f
5356	320	87	BASICO	318	t	f
5357	320	88	BASICO	318	t	f
5358	320	89	BASICO	318	t	f
5359	320	90	BASICO	318	t	f
5360	320	91	BASICO	318	t	f
5361	320	92	BASICO	318	t	f
5362	320	93	BASICO	318	t	f
5363	320	94	BASICO	318	t	f
5364	320	95	BASICO	318	t	f
5365	320	96	BASICO	318	t	f
5366	320	97	BASICO	318	t	f
5367	320	130	BASICO	318	t	f
5368	320	113	INTERMEDIARIO	320	t	f
5369	320	114	INTERMEDIARIO	320	t	f
5370	320	115	INTERMEDIARIO	320	t	f
5371	320	116	BASICO	318	t	f
5372	320	117	INTERMEDIARIO	320	t	f
5373	320	118	BASICO	318	t	f
5374	320	119	BASICO	318	t	f
5375	320	120	BASICO	318	t	f
5376	320	121	BASICO	318	t	f
5377	320	122	BASICO	318	t	f
5378	320	123	BASICO	318	t	f
5379	320	124	BASICO	318	t	f
5380	320	125	BASICO	318	t	f
5381	320	126	BASICO	318	t	f
5382	320	127	BASICO	318	t	f
5383	320	129	BASICO	318	t	f
5384	320	1	BASICO	318	t	f
5385	320	2	BASICO	318	t	f
5386	320	3	BASICO	318	t	f
5387	320	4	BASICO	318	t	f
5388	320	5	BASICO	318	t	f
5389	320	6	BASICO	318	t	f
5390	320	7	BASICO	318	t	f
5391	320	8	BASICO	318	t	f
5392	320	9	BASICO	318	t	f
5393	320	10	BASICO	318	t	f
5394	320	11	BASICO	318	t	f
5395	320	12	BASICO	318	t	f
5396	320	63	INTERMEDIARIO	320	t	f
5397	320	64	BASICO	318	t	f
5398	320	65	BASICO	318	t	f
5399	320	66	BASICO	318	t	f
5400	320	67	BASICO	318	t	f
5401	320	68	BASICO	318	t	f
5402	320	69	BASICO	318	t	f
5403	320	70	BASICO	318	t	f
5404	320	71	BASICO	318	t	f
5405	320	72	BASICO	318	t	f
5406	320	73	BASICO	318	t	f
5407	320	74	BASICO	318	t	f
5408	320	75	BASICO	318	t	f
5409	320	76	BASICO	318	t	f
5410	320	77	BASICO	318	t	f
5411	320	78	BASICO	318	t	f
5412	320	79	BASICO	318	t	f
5413	320	81	BASICO	318	t	f
5414	320	82	INTERMEDIARIO	320	t	f
5415	320	108	BASICO	318	t	f
5416	320	109	BASICO	318	t	f
5417	320	110	BASICO	318	t	f
5418	320	111	BASICO	318	t	f
5419	320	112	BASICO	318	t	f
5420	80	98	INTERMEDIARIO	320	t	f
5421	80	99	AVANCADO	321	t	f
5422	80	100	AVANCADO	321	t	f
5423	80	101	INTERMEDIARIO	320	t	f
5424	80	102	AVANCADO	321	t	f
5425	80	103	INTERMEDIARIO	320	t	f
5426	80	104	INTERMEDIARIO	320	t	f
5427	80	105	INTERMEDIARIO	320	t	f
5428	80	106	INTERMEDIARIO	320	t	f
5429	80	107	AVANCADO	321	t	f
5430	80	47	BASICO	318	t	f
5431	80	48	AVANCADO	321	t	f
5432	80	49	AVANCADO	321	t	f
5433	80	50	BASICO	318	t	f
5434	80	51	INTERMEDIARIO	320	t	f
5435	80	52	BASICO	318	t	f
5436	80	28	INTERMEDIARIO	320	t	f
5437	80	29	INTERMEDIARIO	320	t	f
5438	80	30	INTERMEDIARIO	320	t	f
5439	80	31	INTERMEDIARIO	320	t	f
5440	80	32	INTERMEDIARIO	320	t	f
5441	80	33	INTERMEDIARIO	320	t	f
5442	80	34	INTERMEDIARIO	320	t	f
5443	80	35	INTERMEDIARIO	320	t	f
5444	80	36	INTERMEDIARIO	320	t	f
5445	80	37	INTERMEDIARIO	320	t	f
5446	80	38	AVANCADO	321	t	f
5447	80	39	AVANCADO	321	t	f
5448	80	40	INTERMEDIARIO	320	t	f
5449	80	41	INTERMEDIARIO	320	t	f
5450	80	42	INTERMEDIARIO	320	t	f
5451	80	43	INTERMEDIARIO	320	t	f
5452	80	44	INTERMEDIARIO	320	t	f
5453	80	45	INTERMEDIARIO	320	t	f
5454	80	46	INTERMEDIARIO	320	t	f
5455	80	13	BASICO	318	t	f
5456	80	14	BASICO	318	t	f
5457	80	15	BASICO	318	t	f
5458	80	16	BASICO	318	t	f
5459	80	17	BASICO	318	t	f
5460	80	18	BASICO	318	t	f
5461	80	19	BASICO	318	t	f
5462	80	20	BASICO	318	t	f
5463	80	21	BASICO	318	t	f
5464	80	22	BASICO	318	t	f
5465	80	23	BASICO	318	t	f
5466	80	24	BASICO	318	t	f
5467	80	25	BASICO	318	t	f
5468	80	26	BASICO	318	t	f
5469	80	27	BASICO	318	t	f
5470	80	53	BASICO	318	t	f
5471	80	54	BASICO	318	t	f
5472	80	55	BASICO	318	t	f
5473	80	56	BASICO	318	t	f
5474	80	57	BASICO	318	t	f
5475	80	58	BASICO	318	t	f
5476	80	59	BASICO	318	t	f
5477	80	60	BASICO	318	t	f
5478	80	61	BASICO	318	t	f
5479	80	62	BASICO	318	t	f
5480	80	83	BASICO	318	t	f
5481	80	84	BASICO	318	t	f
5482	80	85	BASICO	318	t	f
5483	80	86	BASICO	318	t	f
5484	80	87	BASICO	318	t	f
5485	80	88	BASICO	318	t	f
5486	80	89	BASICO	318	t	f
5487	80	90	BASICO	318	t	f
5488	80	91	BASICO	318	t	f
5489	80	92	BASICO	318	t	f
5490	80	93	BASICO	318	t	f
5491	80	94	BASICO	318	t	f
5492	80	95	BASICO	318	t	f
5493	80	96	INTERMEDIARIO	320	t	f
5494	80	97	BASICO	318	t	f
5495	80	130	BASICO	318	t	f
5496	80	113	BASICO	318	t	f
5497	80	114	BASICO	318	t	f
5498	80	115	INTERMEDIARIO	320	t	f
5499	80	116	BASICO	318	t	f
5500	80	117	INTERMEDIARIO	320	t	f
5501	80	118	BASICO	318	t	f
5502	80	119	BASICO	318	t	f
5503	80	120	BASICO	318	t	f
5504	80	121	BASICO	318	t	f
5505	80	122	BASICO	318	t	f
5506	80	123	BASICO	318	t	f
5507	80	124	BASICO	318	t	f
5508	80	125	BASICO	318	t	f
5509	80	126	BASICO	318	t	f
5510	80	127	BASICO	318	t	f
5511	80	129	BASICO	318	t	f
5512	80	1	AVANCADO	321	t	f
5513	80	2	AVANCADO	321	t	f
5514	80	3	INTERMEDIARIO	320	t	f
5515	80	4	INTERMEDIARIO	320	t	f
5516	80	5	INTERMEDIARIO	320	t	f
5517	80	6	INTERMEDIARIO	320	t	f
5518	80	7	INTERMEDIARIO	320	t	f
5519	80	8	INTERMEDIARIO	320	t	f
5520	80	9	AVANCADO	321	t	f
5521	80	10	AVANCADO	321	t	f
5522	80	11	AVANCADO	321	t	f
5523	80	12	AVANCADO	321	t	f
5524	80	63	BASICO	318	t	f
5525	80	64	BASICO	318	t	f
5526	80	65	BASICO	318	t	f
5527	80	66	BASICO	318	t	f
5528	80	67	BASICO	318	t	f
5529	80	68	BASICO	318	t	f
5530	80	69	BASICO	318	t	f
5531	80	70	BASICO	318	t	f
5532	80	71	BASICO	318	t	f
5533	80	72	BASICO	318	t	f
5534	80	73	BASICO	318	t	f
5535	80	74	BASICO	318	t	f
5536	80	75	BASICO	318	t	f
5537	80	76	BASICO	318	t	f
5538	80	77	BASICO	318	t	f
5539	80	78	BASICO	318	t	f
5540	80	79	BASICO	318	t	f
5541	80	81	BASICO	318	t	f
5542	80	82	INTERMEDIARIO	320	t	f
5543	80	108	BASICO	318	t	f
5544	80	109	BASICO	318	t	f
5545	80	110	BASICO	318	t	f
5546	80	111	BASICO	318	t	f
5547	80	112	BASICO	318	t	f
5548	270	98	INTERMEDIARIO	320	t	f
5549	270	101	INTERMEDIARIO	320	t	f
5550	270	102	INTERMEDIARIO	320	t	f
5551	270	104	INTERMEDIARIO	320	t	f
5552	270	105	BASICO	318	t	f
5553	270	106	AVANCADO	321	t	f
5554	270	51	INTERMEDIARIO	320	t	f
5555	270	84	BASICO	318	t	f
5556	11	98	INTERMEDIARIO	320	t	f
5557	11	103	INTERMEDIARIO	320	t	f
5558	11	104	INTERMEDIARIO	320	t	f
5559	11	105	AVANCADO	321	t	f
5560	11	107	INTERMEDIARIO	320	t	f
5561	11	47	INTERMEDIARIO	320	t	f
5562	11	51	INTERMEDIARIO	320	t	f
5563	11	28	INTERMEDIARIO	320	t	f
5564	11	30	INTERMEDIARIO	320	t	f
5565	11	46	INTERMEDIARIO	320	t	f
5566	11	16	INTERMEDIARIO	320	t	f
5567	11	26	INTERMEDIARIO	320	t	f
5568	11	56	INTERMEDIARIO	320	t	f
5569	11	58	INTERMEDIARIO	320	t	f
5570	11	59	BASICO	318	t	f
5571	11	87	BASICO	318	t	f
5572	11	116	BASICO	318	t	f
5573	11	108	BASICO	318	t	f
5574	182	98	BASICO	318	t	f
5575	182	102	BASICO	318	t	f
5576	182	105	BASICO	318	t	f
5577	182	106	INTERMEDIARIO	320	t	f
5578	182	107	BASICO	318	t	f
5579	182	51	BASICO	318	t	f
5580	182	29	BASICO	318	t	f
5581	182	16	INTERMEDIARIO	320	t	f
5582	182	56	BASICO	318	t	f
5583	182	84	BASICO	318	t	f
5584	182	87	BASICO	318	t	f
5585	182	91	INTERMEDIARIO	320	t	f
5586	182	92	BASICO	318	t	f
5587	182	94	INTERMEDIARIO	320	t	f
5588	182	96	AVANCADO	321	t	f
5589	182	130	BASICO	318	t	f
5590	50	98	BASICO	318	t	f
5591	50	102	INTERMEDIARIO	320	t	f
5592	50	35	BASICO	318	t	f
5593	50	38	INTERMEDIARIO	320	t	f
5594	50	16	INTERMEDIARIO	320	t	f
5595	50	21	INTERMEDIARIO	320	t	f
5596	50	55	BASICO	318	t	f
5597	50	56	INTERMEDIARIO	320	t	f
5598	50	117	INTERMEDIARIO	320	t	f
5599	50	119	INTERMEDIARIO	320	t	f
5600	50	64	INTERMEDIARIO	320	t	f
5601	50	72	INTERMEDIARIO	320	t	f
5602	50	82	BASICO	318	t	f
5603	50	110	AVANCADO	321	t	f
5604	50	111	INTERMEDIARIO	320	t	f
5605	225	107	BASICO	318	t	f
5606	225	50	INTERMEDIARIO	320	t	f
5607	225	52	AVANCADO	321	t	f
5608	225	29	INTERMEDIARIO	320	t	f
5609	225	40	AVANCADO	321	t	f
5610	225	42	BASICO	318	t	f
5611	225	43	INTERMEDIARIO	320	t	f
5612	225	15	AVANCADO	321	t	f
5613	225	53	BASICO	318	t	f
5614	225	54	BASICO	318	t	f
5615	225	55	AVANCADO	321	t	f
5616	225	56	AVANCADO	321	t	f
5617	225	58	AVANCADO	321	t	f
5618	225	84	BASICO	318	t	f
5619	225	86	BASICO	318	t	f
5620	225	94	BASICO	318	t	f
5621	225	114	INTERMEDIARIO	320	t	f
5622	225	115	AVANCADO	321	t	f
5623	225	116	INTERMEDIARIO	320	t	f
5624	225	117	INTERMEDIARIO	320	t	f
5625	225	124	INTERMEDIARIO	320	t	f
5626	225	126	INTERMEDIARIO	320	t	f
5627	225	129	INTERMEDIARIO	320	t	f
5628	225	1	INTERMEDIARIO	320	t	f
5629	225	4	BASICO	318	t	f
5630	225	7	BASICO	318	t	f
5631	225	8	AVANCADO	321	t	f
5632	225	66	INTERMEDIARIO	320	t	f
5633	225	68	INTERMEDIARIO	320	t	f
5634	225	72	INTERMEDIARIO	320	t	f
5635	225	73	INTERMEDIARIO	320	t	f
5636	225	76	INTERMEDIARIO	320	t	f
5637	225	78	INTERMEDIARIO	320	t	f
5638	225	79	INTERMEDIARIO	320	t	f
5639	225	108	INTERMEDIARIO	320	t	f
5640	225	109	INTERMEDIARIO	320	t	f
5641	225	111	INTERMEDIARIO	320	t	f
5642	221	98	BASICO	318	t	f
5643	221	99	BASICO	318	t	f
5644	221	100	BASICO	318	t	f
5645	221	101	BASICO	318	t	f
5646	221	102	BASICO	318	t	f
5647	221	103	INTERMEDIARIO	320	t	f
5648	221	104	BASICO	318	t	f
5649	221	105	INTERMEDIARIO	320	t	f
5650	221	106	INTERMEDIARIO	320	t	f
5651	221	107	BASICO	318	t	f
5652	221	47	BASICO	318	t	f
5653	221	48	BASICO	318	t	f
5654	221	49	BASICO	318	t	f
5655	221	50	BASICO	318	t	f
5656	221	51	BASICO	318	t	f
5657	221	52	BASICO	318	t	f
5658	221	28	BASICO	318	t	f
5659	221	29	INTERMEDIARIO	320	t	f
5660	221	30	BASICO	318	t	f
5661	221	31	BASICO	318	t	f
5662	221	32	BASICO	318	t	f
5663	221	33	BASICO	318	t	f
5664	221	34	BASICO	318	t	f
5665	221	35	INTERMEDIARIO	320	t	f
5666	221	36	INTERMEDIARIO	320	t	f
5667	221	37	INTERMEDIARIO	320	t	f
5668	221	38	INTERMEDIARIO	320	t	f
5669	221	39	BASICO	318	t	f
5670	221	40	INTERMEDIARIO	320	t	f
5671	221	41	INTERMEDIARIO	320	t	f
5672	221	42	BASICO	318	t	f
5673	221	43	BASICO	318	t	f
5674	221	44	BASICO	318	t	f
5675	221	45	BASICO	318	t	f
5676	221	46	BASICO	318	t	f
5677	221	13	BASICO	318	t	f
5678	221	14	INTERMEDIARIO	320	t	f
5679	221	15	BASICO	318	t	f
5680	221	16	BASICO	318	t	f
5681	221	17	BASICO	318	t	f
5682	221	18	BASICO	318	t	f
5683	221	19	BASICO	318	t	f
5684	221	21	INTERMEDIARIO	320	t	f
5685	221	22	BASICO	318	t	f
5686	221	23	BASICO	318	t	f
5687	221	24	BASICO	318	t	f
5688	221	25	BASICO	318	t	f
5689	221	26	BASICO	318	t	f
5690	221	27	BASICO	318	t	f
5691	221	53	BASICO	318	t	f
5692	221	54	BASICO	318	t	f
5693	221	55	INTERMEDIARIO	320	t	f
5694	221	56	INTERMEDIARIO	320	t	f
5695	221	57	BASICO	318	t	f
5696	221	58	BASICO	318	t	f
5697	221	59	BASICO	318	t	f
5698	221	60	BASICO	318	t	f
5699	221	61	BASICO	318	t	f
5700	221	62	BASICO	318	t	f
5701	221	83	BASICO	318	t	f
5702	221	84	BASICO	318	t	f
5703	221	85	BASICO	318	t	f
5704	221	86	BASICO	318	t	f
5705	221	87	BASICO	318	t	f
5706	221	88	BASICO	318	t	f
5707	221	89	BASICO	318	t	f
5708	221	90	BASICO	318	t	f
5709	221	91	BASICO	318	t	f
5710	221	92	BASICO	318	t	f
5711	221	93	BASICO	318	t	f
5712	221	94	BASICO	318	t	f
5713	221	95	BASICO	318	t	f
5714	221	96	BASICO	318	t	f
5715	221	97	BASICO	318	t	f
5716	221	130	BASICO	318	t	f
5717	221	113	BASICO	318	t	f
5718	221	115	INTERMEDIARIO	320	t	f
5719	221	116	INTERMEDIARIO	320	t	f
5720	221	117	INTERMEDIARIO	320	t	f
5721	221	118	INTERMEDIARIO	320	t	f
5722	221	119	INTERMEDIARIO	320	t	f
5723	221	120	BASICO	318	t	f
5724	221	121	BASICO	318	t	f
5725	221	122	BASICO	318	t	f
5726	221	123	BASICO	318	t	f
5727	221	124	BASICO	318	t	f
5728	221	125	BASICO	318	t	f
5729	221	126	BASICO	318	t	f
5730	221	127	BASICO	318	t	f
5731	221	129	BASICO	318	t	f
5732	221	1	INTERMEDIARIO	320	t	f
5733	221	2	BASICO	318	t	f
5734	221	3	BASICO	318	t	f
5735	221	4	BASICO	318	t	f
5736	221	5	BASICO	318	t	f
5737	221	6	BASICO	318	t	f
5738	221	7	BASICO	318	t	f
5739	221	8	BASICO	318	t	f
5740	221	9	BASICO	318	t	f
5741	221	10	BASICO	318	t	f
5742	221	11	BASICO	318	t	f
5743	221	12	BASICO	318	t	f
5744	221	63	BASICO	318	t	f
5745	221	64	INTERMEDIARIO	320	t	f
5746	221	65	BASICO	318	t	f
5747	221	66	BASICO	318	t	f
5748	221	67	BASICO	318	t	f
5749	221	68	INTERMEDIARIO	320	t	f
5750	221	69	BASICO	318	t	f
5751	221	70	BASICO	318	t	f
5752	221	71	BASICO	318	t	f
5753	221	72	INTERMEDIARIO	320	t	f
5754	221	73	BASICO	318	t	f
5755	221	74	BASICO	318	t	f
5756	221	75	BASICO	318	t	f
5757	221	76	BASICO	318	t	f
5758	221	77	BASICO	318	t	f
5759	221	78	BASICO	318	t	f
5760	221	79	BASICO	318	t	f
5761	221	81	BASICO	318	t	f
5762	221	82	BASICO	318	t	f
5763	221	108	INTERMEDIARIO	320	t	f
5764	221	109	BASICO	318	t	f
5765	221	110	INTERMEDIARIO	320	t	f
5766	221	111	BASICO	318	t	f
5767	221	112	INTERMEDIARIO	320	t	f
5768	286	98	BASICO	318	t	f
5769	286	99	BASICO	318	t	f
5770	286	100	BASICO	318	t	f
5771	286	101	BASICO	318	t	f
5772	286	102	BASICO	318	t	f
5773	286	104	INTERMEDIARIO	320	t	f
5774	286	105	BASICO	318	t	f
5775	286	106	AVANCADO	321	t	f
5776	286	107	AVANCADO	321	t	f
5777	286	47	BASICO	318	t	f
5778	286	48	BASICO	318	t	f
5779	286	49	INTERMEDIARIO	320	t	f
5780	286	50	INTERMEDIARIO	320	t	f
5781	286	28	INTERMEDIARIO	320	t	f
5782	286	29	AVANCADO	321	t	f
5783	286	30	INTERMEDIARIO	320	t	f
5784	286	31	BASICO	318	t	f
5785	286	32	BASICO	318	t	f
5786	286	33	INTERMEDIARIO	320	t	f
5787	286	34	INTERMEDIARIO	320	t	f
5788	286	35	BASICO	318	t	f
5789	286	36	AVANCADO	321	t	f
5790	286	37	BASICO	318	t	f
5791	286	39	BASICO	318	t	f
5792	286	40	AVANCADO	321	t	f
5793	286	41	AVANCADO	321	t	f
5794	286	42	INTERMEDIARIO	320	t	f
5795	286	43	INTERMEDIARIO	320	t	f
5796	286	44	BASICO	318	t	f
5797	286	46	BASICO	318	t	f
5798	286	13	BASICO	318	t	f
5799	286	15	AVANCADO	321	t	f
5800	286	16	BASICO	318	t	f
5801	286	17	INTERMEDIARIO	320	t	f
5802	286	18	INTERMEDIARIO	320	t	f
5803	286	20	INTERMEDIARIO	320	t	f
5804	286	22	BASICO	318	t	f
5805	286	23	BASICO	318	t	f
5806	286	24	BASICO	318	t	f
5807	286	25	BASICO	318	t	f
5808	286	26	BASICO	318	t	f
5809	286	27	BASICO	318	t	f
5810	286	53	BASICO	318	t	f
5811	286	54	BASICO	318	t	f
5812	286	57	BASICO	318	t	f
5813	286	60	INTERMEDIARIO	320	t	f
5814	286	61	INTERMEDIARIO	320	t	f
5815	286	62	AVANCADO	321	t	f
5816	286	83	BASICO	318	t	f
5817	286	84	BASICO	318	t	f
5818	286	85	BASICO	318	t	f
5819	286	86	INTERMEDIARIO	320	t	f
5820	286	87	BASICO	318	t	f
5821	286	88	BASICO	318	t	f
5822	286	89	INTERMEDIARIO	320	t	f
5823	286	90	BASICO	318	t	f
5824	286	91	BASICO	318	t	f
5825	286	92	BASICO	318	t	f
5826	286	93	BASICO	318	t	f
5827	286	94	BASICO	318	t	f
5828	286	95	BASICO	318	t	f
5829	286	96	BASICO	318	t	f
5830	286	97	BASICO	318	t	f
5831	286	130	BASICO	318	t	f
5832	286	113	INTERMEDIARIO	320	t	f
5833	286	114	AVANCADO	321	t	f
5834	286	116	INTERMEDIARIO	320	t	f
5835	286	118	AVANCADO	321	t	f
5836	286	119	INTERMEDIARIO	320	t	f
5837	286	120	INTERMEDIARIO	320	t	f
5838	286	121	BASICO	318	t	f
5839	286	122	BASICO	318	t	f
5840	286	123	INTERMEDIARIO	320	t	f
5841	286	124	INTERMEDIARIO	320	t	f
5842	286	125	BASICO	318	t	f
5843	286	126	BASICO	318	t	f
5844	286	127	BASICO	318	t	f
5845	286	129	AVANCADO	321	t	f
5846	286	1	INTERMEDIARIO	320	t	f
5847	286	2	BASICO	318	t	f
5848	286	3	BASICO	318	t	f
5849	286	4	AVANCADO	321	t	f
5850	286	5	BASICO	318	t	f
5851	286	6	BASICO	318	t	f
5852	286	7	AVANCADO	321	t	f
5853	286	8	AVANCADO	321	t	f
5854	286	9	AVANCADO	321	t	f
5855	286	10	INTERMEDIARIO	320	t	f
5856	286	11	BASICO	318	t	f
5857	286	12	AVANCADO	321	t	f
5858	286	63	INTERMEDIARIO	320	t	f
5859	286	64	BASICO	318	t	f
5860	286	66	AVANCADO	321	t	f
5861	286	67	BASICO	318	t	f
5862	286	68	INTERMEDIARIO	320	t	f
5863	286	69	BASICO	318	t	f
5864	286	70	BASICO	318	t	f
5865	286	71	INTERMEDIARIO	320	t	f
5866	286	72	INTERMEDIARIO	320	t	f
5867	286	73	BASICO	318	t	f
5868	286	74	BASICO	318	t	f
5869	286	75	INTERMEDIARIO	320	t	f
5870	286	76	INTERMEDIARIO	320	t	f
5871	286	77	BASICO	318	t	f
5872	286	78	BASICO	318	t	f
5873	286	79	INTERMEDIARIO	320	t	f
5874	286	81	BASICO	318	t	f
5875	286	82	BASICO	318	t	f
5876	286	108	INTERMEDIARIO	320	t	f
5877	286	109	INTERMEDIARIO	320	t	f
5878	286	110	BASICO	318	t	f
5879	286	111	INTERMEDIARIO	320	t	f
5880	286	112	BASICO	318	t	f
5881	33	99	BASICO	318	t	f
5882	33	100	BASICO	318	t	f
5883	33	102	BASICO	318	t	f
5884	33	103	INTERMEDIARIO	320	t	f
5885	33	104	INTERMEDIARIO	320	t	f
5886	33	106	INTERMEDIARIO	320	t	f
5887	33	107	BASICO	318	t	f
5888	33	49	BASICO	318	t	f
5889	33	51	BASICO	318	t	f
5890	33	29	AVANCADO	321	t	f
5891	33	31	AVANCADO	321	t	f
5892	33	33	AVANCADO	321	t	f
5893	33	34	INTERMEDIARIO	320	t	f
5894	33	36	AVANCADO	321	t	f
5895	33	37	AVANCADO	321	t	f
5896	33	38	AVANCADO	321	t	f
5897	33	39	AVANCADO	321	t	f
5898	33	40	AVANCADO	321	t	f
5899	33	41	AVANCADO	321	t	f
5900	33	42	BASICO	318	t	f
5901	33	43	AVANCADO	321	t	f
5902	33	44	AVANCADO	321	t	f
5903	33	45	BASICO	318	t	f
5904	33	46	BASICO	318	t	f
5905	33	113	AVANCADO	321	t	f
5906	33	114	BASICO	318	t	f
5907	33	115	INTERMEDIARIO	320	t	f
5908	33	116	INTERMEDIARIO	320	t	f
5909	33	117	BASICO	318	t	f
5910	33	119	AVANCADO	321	t	f
5911	33	120	BASICO	318	t	f
5912	33	121	AVANCADO	321	t	f
5913	33	122	BASICO	318	t	f
5914	33	123	BASICO	318	t	f
5915	33	124	AVANCADO	321	t	f
5916	33	125	BASICO	318	t	f
5917	33	126	AVANCADO	321	t	f
5918	33	127	BASICO	318	t	f
5919	33	129	AVANCADO	321	t	f
5920	33	1	BASICO	318	t	f
5921	33	2	BASICO	318	t	f
5922	33	8	BASICO	318	t	f
5923	33	9	BASICO	318	t	f
5924	33	10	BASICO	318	t	f
5925	33	12	BASICO	318	t	f
5926	33	65	AVANCADO	321	t	f
5927	33	66	AVANCADO	321	t	f
5928	33	67	AVANCADO	321	t	f
5929	33	68	BASICO	318	t	f
5930	33	69	BASICO	318	t	f
5931	33	70	AVANCADO	321	t	f
5932	33	72	AVANCADO	321	t	f
5933	33	73	AVANCADO	321	t	f
5934	33	74	INTERMEDIARIO	320	t	f
5935	33	75	AVANCADO	321	t	f
5936	33	76	AVANCADO	321	t	f
5937	33	77	AVANCADO	321	t	f
5938	33	78	BASICO	318	t	f
5939	33	79	BASICO	318	t	f
5940	33	81	BASICO	318	t	f
5941	33	82	AVANCADO	321	t	f
5942	33	110	BASICO	318	t	f
5943	33	111	BASICO	318	t	f
5944	33	112	BASICO	318	t	f
5945	82	98	INTERMEDIARIO	320	t	f
5946	82	99	BASICO	318	t	f
5947	82	100	INTERMEDIARIO	320	t	f
5948	82	101	INTERMEDIARIO	320	t	f
5949	82	102	AVANCADO	321	t	f
5950	82	103	AVANCADO	321	t	f
5951	82	104	BASICO	318	t	f
5952	82	105	AVANCADO	321	t	f
5953	82	106	AVANCADO	321	t	f
5954	82	107	AVANCADO	321	t	f
5955	82	47	BASICO	318	t	f
5956	82	48	BASICO	318	t	f
5957	82	49	AVANCADO	321	t	f
5958	82	50	AVANCADO	321	t	f
5959	82	51	BASICO	318	t	f
5960	82	52	BASICO	318	t	f
5961	82	28	INTERMEDIARIO	320	t	f
5962	82	29	INTERMEDIARIO	320	t	f
5963	82	30	AVANCADO	321	t	f
5964	82	31	BASICO	318	t	f
5965	82	32	BASICO	318	t	f
5966	82	34	AVANCADO	321	t	f
5967	82	35	AVANCADO	321	t	f
5968	82	36	AVANCADO	321	t	f
5969	82	37	AVANCADO	321	t	f
5970	82	38	INTERMEDIARIO	320	t	f
5971	82	39	AVANCADO	321	t	f
5972	82	40	AVANCADO	321	t	f
5973	82	41	AVANCADO	321	t	f
5974	82	42	BASICO	318	t	f
5975	82	43	INTERMEDIARIO	320	t	f
5976	82	44	AVANCADO	321	t	f
5977	82	45	BASICO	318	t	f
5978	82	46	BASICO	318	t	f
5979	82	13	BASICO	318	t	f
5980	82	14	INTERMEDIARIO	320	t	f
5981	82	15	AVANCADO	321	t	f
5982	82	16	AVANCADO	321	t	f
5983	82	17	AVANCADO	321	t	f
5984	82	18	BASICO	318	t	f
5985	82	19	AVANCADO	321	t	f
5986	82	20	BASICO	318	t	f
5987	82	21	AVANCADO	321	t	f
5988	82	22	AVANCADO	321	t	f
5989	82	23	INTERMEDIARIO	320	t	f
5990	82	24	BASICO	318	t	f
5991	82	25	BASICO	318	t	f
5992	82	26	AVANCADO	321	t	f
5993	82	27	BASICO	318	t	f
5994	82	53	BASICO	318	t	f
5995	82	54	BASICO	318	t	f
5996	82	55	AVANCADO	321	t	f
5997	82	56	AVANCADO	321	t	f
5998	82	57	BASICO	318	t	f
5999	82	58	BASICO	318	t	f
6000	82	59	INTERMEDIARIO	320	t	f
6001	82	60	BASICO	318	t	f
6002	82	62	INTERMEDIARIO	320	t	f
6003	82	83	BASICO	318	t	f
6004	82	84	BASICO	318	t	f
6005	82	85	INTERMEDIARIO	320	t	f
6006	82	86	BASICO	318	t	f
6007	82	87	BASICO	318	t	f
6008	82	88	BASICO	318	t	f
6009	82	90	BASICO	318	t	f
6010	82	91	AVANCADO	321	t	f
6011	82	92	AVANCADO	321	t	f
6012	82	93	BASICO	318	t	f
6013	82	94	BASICO	318	t	f
6014	82	95	BASICO	318	t	f
6015	82	96	AVANCADO	321	t	f
6016	82	97	BASICO	318	t	f
6017	82	130	AVANCADO	321	t	f
6018	82	113	AVANCADO	321	t	f
6019	82	114	BASICO	318	t	f
6020	82	115	AVANCADO	321	t	f
6021	82	116	AVANCADO	321	t	f
6022	82	117	AVANCADO	321	t	f
6023	82	118	AVANCADO	321	t	f
6024	82	119	AVANCADO	321	t	f
6025	82	120	AVANCADO	321	t	f
6026	82	121	BASICO	318	t	f
6027	82	122	BASICO	318	t	f
6028	82	123	BASICO	318	t	f
6029	82	124	BASICO	318	t	f
6030	82	125	BASICO	318	t	f
6031	82	126	BASICO	318	t	f
6032	82	127	BASICO	318	t	f
6033	82	129	INTERMEDIARIO	320	t	f
6034	82	1	AVANCADO	321	t	f
6035	82	2	INTERMEDIARIO	320	t	f
6036	82	3	BASICO	318	t	f
6037	82	4	BASICO	318	t	f
6038	82	5	BASICO	318	t	f
6039	82	6	BASICO	318	t	f
6040	82	7	BASICO	318	t	f
6041	82	8	AVANCADO	321	t	f
6042	82	9	BASICO	318	t	f
6043	82	10	INTERMEDIARIO	320	t	f
6044	82	11	AVANCADO	321	t	f
6045	82	12	AVANCADO	321	t	f
6046	82	63	AVANCADO	321	t	f
6047	82	64	AVANCADO	321	t	f
6048	82	65	AVANCADO	321	t	f
6049	82	66	AVANCADO	321	t	f
6050	82	67	BASICO	318	t	f
6051	82	68	INTERMEDIARIO	320	t	f
6052	82	69	BASICO	318	t	f
6053	82	70	BASICO	318	t	f
6054	82	71	AVANCADO	321	t	f
6055	82	72	BASICO	318	t	f
6056	82	73	INTERMEDIARIO	320	t	f
6057	82	74	BASICO	318	t	f
6058	82	75	INTERMEDIARIO	320	t	f
6059	82	76	INTERMEDIARIO	320	t	f
6060	82	77	BASICO	318	t	f
6061	82	78	INTERMEDIARIO	320	t	f
6062	82	79	AVANCADO	321	t	f
6063	82	81	BASICO	318	t	f
6064	82	82	AVANCADO	321	t	f
6065	82	108	AVANCADO	321	t	f
6066	82	109	BASICO	318	t	f
6067	82	110	BASICO	318	t	f
6068	82	111	BASICO	318	t	f
6069	82	112	BASICO	318	t	f
6070	295	103	BASICO	318	t	f
6071	295	105	BASICO	318	t	f
6072	295	51	BASICO	318	t	f
6073	295	38	BASICO	318	t	f
6074	295	16	BASICO	318	t	f
6075	295	21	BASICO	318	t	f
6076	295	58	BASICO	318	t	f
6077	295	96	BASICO	318	t	f
6078	295	1	BASICO	318	t	f
6079	100	98	INTERMEDIARIO	320	t	f
6080	100	99	BASICO	318	t	f
6081	100	100	BASICO	318	t	f
6082	100	101	BASICO	318	t	f
6083	100	102	BASICO	318	t	f
6084	100	103	BASICO	318	t	f
6085	100	104	BASICO	318	t	f
6086	100	105	BASICO	318	t	f
6087	100	106	INTERMEDIARIO	320	t	f
6088	100	107	INTERMEDIARIO	320	t	f
6089	100	47	BASICO	318	t	f
6090	100	48	BASICO	318	t	f
6091	100	49	BASICO	318	t	f
6092	100	50	BASICO	318	t	f
6093	100	51	BASICO	318	t	f
6094	100	52	BASICO	318	t	f
6095	100	28	INTERMEDIARIO	320	t	f
6096	100	29	INTERMEDIARIO	320	t	f
6097	100	30	INTERMEDIARIO	320	t	f
6098	100	32	BASICO	318	t	f
6099	100	33	BASICO	318	t	f
6100	100	34	BASICO	318	t	f
6101	100	35	INTERMEDIARIO	320	t	f
6102	100	36	INTERMEDIARIO	320	t	f
6103	100	37	INTERMEDIARIO	320	t	f
6104	100	38	INTERMEDIARIO	320	t	f
6105	100	39	INTERMEDIARIO	320	t	f
6106	100	40	INTERMEDIARIO	320	t	f
6107	100	41	INTERMEDIARIO	320	t	f
6108	100	42	INTERMEDIARIO	320	t	f
6109	100	43	INTERMEDIARIO	320	t	f
6110	100	44	INTERMEDIARIO	320	t	f
6111	100	45	BASICO	318	t	f
6112	100	46	BASICO	318	t	f
6113	100	13	INTERMEDIARIO	320	t	f
6114	100	14	BASICO	318	t	f
6115	100	15	INTERMEDIARIO	320	t	f
6116	100	16	BASICO	318	t	f
6117	100	17	BASICO	318	t	f
6118	100	18	INTERMEDIARIO	320	t	f
6119	100	19	INTERMEDIARIO	320	t	f
6120	100	20	INTERMEDIARIO	320	t	f
6121	100	21	BASICO	318	t	f
6122	100	22	BASICO	318	t	f
6123	100	23	BASICO	318	t	f
6124	100	24	BASICO	318	t	f
6125	100	25	BASICO	318	t	f
6126	100	26	BASICO	318	t	f
6127	100	27	BASICO	318	t	f
6128	100	53	BASICO	318	t	f
6129	100	54	BASICO	318	t	f
6130	100	55	INTERMEDIARIO	320	t	f
6131	100	56	INTERMEDIARIO	320	t	f
6132	100	57	BASICO	318	t	f
6133	100	58	INTERMEDIARIO	320	t	f
6134	100	59	INTERMEDIARIO	320	t	f
6135	100	60	INTERMEDIARIO	320	t	f
6136	100	61	INTERMEDIARIO	320	t	f
6137	100	62	INTERMEDIARIO	320	t	f
6138	100	83	BASICO	318	t	f
6139	100	84	INTERMEDIARIO	320	t	f
6140	100	85	INTERMEDIARIO	320	t	f
6141	100	86	BASICO	318	t	f
6142	100	87	BASICO	318	t	f
6143	100	88	BASICO	318	t	f
6144	100	89	BASICO	318	t	f
6145	100	90	BASICO	318	t	f
6146	100	91	INTERMEDIARIO	320	t	f
6147	100	92	INTERMEDIARIO	320	t	f
6148	100	93	BASICO	318	t	f
6149	100	94	INTERMEDIARIO	320	t	f
6150	100	95	BASICO	318	t	f
6151	100	96	BASICO	318	t	f
6152	100	97	BASICO	318	t	f
6153	100	130	BASICO	318	t	f
6154	100	113	INTERMEDIARIO	320	t	f
6155	100	114	INTERMEDIARIO	320	t	f
6156	100	115	INTERMEDIARIO	320	t	f
6157	100	116	INTERMEDIARIO	320	t	f
6158	100	117	INTERMEDIARIO	320	t	f
6159	100	118	INTERMEDIARIO	320	t	f
6160	100	119	INTERMEDIARIO	320	t	f
6161	100	120	INTERMEDIARIO	320	t	f
6162	100	121	INTERMEDIARIO	320	t	f
6163	100	122	BASICO	318	t	f
6164	100	124	INTERMEDIARIO	320	t	f
6165	100	129	INTERMEDIARIO	320	t	f
6166	100	1	INTERMEDIARIO	320	t	f
6167	100	2	BASICO	318	t	f
6168	100	3	BASICO	318	t	f
6169	100	4	BASICO	318	t	f
6170	100	5	BASICO	318	t	f
6171	100	6	INTERMEDIARIO	320	t	f
6172	100	7	INTERMEDIARIO	320	t	f
6173	100	8	INTERMEDIARIO	320	t	f
6174	100	9	INTERMEDIARIO	320	t	f
6175	100	10	INTERMEDIARIO	320	t	f
6176	100	11	BASICO	318	t	f
6177	100	12	INTERMEDIARIO	320	t	f
6178	100	63	INTERMEDIARIO	320	t	f
6179	100	64	INTERMEDIARIO	320	t	f
6180	100	65	INTERMEDIARIO	320	t	f
6181	100	66	INTERMEDIARIO	320	t	f
6182	100	67	INTERMEDIARIO	320	t	f
6183	100	68	INTERMEDIARIO	320	t	f
6184	100	69	BASICO	318	t	f
6185	100	70	BASICO	318	t	f
6186	100	71	BASICO	318	t	f
6187	100	72	INTERMEDIARIO	320	t	f
6188	100	73	BASICO	318	t	f
6189	100	74	BASICO	318	t	f
6190	100	75	INTERMEDIARIO	320	t	f
6191	100	76	INTERMEDIARIO	320	t	f
6192	100	77	BASICO	318	t	f
6193	100	78	BASICO	318	t	f
6194	100	79	BASICO	318	t	f
6195	100	81	BASICO	318	t	f
6196	100	82	INTERMEDIARIO	320	t	f
6197	100	108	INTERMEDIARIO	320	t	f
6198	100	109	INTERMEDIARIO	320	t	f
6199	100	110	INTERMEDIARIO	320	t	f
6200	100	111	INTERMEDIARIO	320	t	f
6201	100	112	INTERMEDIARIO	320	t	f
6202	10	100	BASICO	318	t	f
6203	10	50	BASICO	318	t	f
6204	10	35	BASICO	318	t	f
6205	10	44	BASICO	318	t	f
6206	10	14	BASICO	318	t	f
6207	10	20	BASICO	318	t	f
6208	10	21	INTERMEDIARIO	320	t	f
6209	10	55	BASICO	318	t	f
6210	10	56	BASICO	318	t	f
6211	10	58	BASICO	318	t	f
6212	10	1	BASICO	318	t	f
6213	10	2	BASICO	318	t	f
6214	10	63	BASICO	318	t	f
6215	10	82	BASICO	318	t	f
6216	317	98	BASICO	318	t	f
6217	317	99	BASICO	318	t	f
6218	317	100	BASICO	318	t	f
6219	317	101	BASICO	318	t	f
6220	317	102	BASICO	318	t	f
6221	317	103	BASICO	318	t	f
6222	317	104	INTERMEDIARIO	320	t	f
6223	317	105	BASICO	318	t	f
6224	317	106	INTERMEDIARIO	320	t	f
6225	317	107	INTERMEDIARIO	320	t	f
6226	317	47	BASICO	318	t	f
6227	317	48	BASICO	318	t	f
6228	317	49	INTERMEDIARIO	320	t	f
6229	317	50	INTERMEDIARIO	320	t	f
6230	317	51	INTERMEDIARIO	320	t	f
6231	317	52	AVANCADO	321	t	f
6232	317	28	BASICO	318	t	f
6233	317	29	AVANCADO	321	t	f
6234	317	30	INTERMEDIARIO	320	t	f
6235	317	31	INTERMEDIARIO	320	t	f
6236	317	32	BASICO	318	t	f
6237	317	33	AVANCADO	321	t	f
6238	317	34	AVANCADO	321	t	f
6239	317	35	INTERMEDIARIO	320	t	f
6240	317	36	AVANCADO	321	t	f
6241	317	37	INTERMEDIARIO	320	t	f
6242	317	38	INTERMEDIARIO	320	t	f
6243	317	39	BASICO	318	t	f
6244	317	40	AVANCADO	321	t	f
6245	317	41	AVANCADO	321	t	f
6246	317	42	INTERMEDIARIO	320	t	f
6247	317	43	INTERMEDIARIO	320	t	f
6248	317	44	AVANCADO	321	t	f
6249	317	46	BASICO	318	t	f
6250	317	13	AVANCADO	321	t	f
6251	317	14	INTERMEDIARIO	320	t	f
6252	317	15	AVANCADO	321	t	f
6253	317	16	INTERMEDIARIO	320	t	f
6254	317	17	INTERMEDIARIO	320	t	f
6255	317	18	AVANCADO	321	t	f
6256	317	19	AVANCADO	321	t	f
6257	317	20	AVANCADO	321	t	f
6258	317	21	AVANCADO	321	t	f
6259	317	22	BASICO	318	t	f
6260	317	23	BASICO	318	t	f
6261	317	24	BASICO	318	t	f
6262	317	25	BASICO	318	t	f
6263	317	26	BASICO	318	t	f
6264	317	27	INTERMEDIARIO	320	t	f
6265	317	53	AVANCADO	321	t	f
6266	317	54	AVANCADO	321	t	f
6267	317	55	AVANCADO	321	t	f
6268	317	56	AVANCADO	321	t	f
6269	317	57	AVANCADO	321	t	f
6270	317	58	AVANCADO	321	t	f
6271	317	59	INTERMEDIARIO	320	t	f
6272	317	60	INTERMEDIARIO	320	t	f
6273	317	61	INTERMEDIARIO	320	t	f
6274	317	62	AVANCADO	321	t	f
6275	317	83	BASICO	318	t	f
6276	317	84	BASICO	318	t	f
6277	317	85	BASICO	318	t	f
6278	317	86	INTERMEDIARIO	320	t	f
6279	317	87	BASICO	318	t	f
6280	317	88	BASICO	318	t	f
6281	317	89	BASICO	318	t	f
6282	317	90	AVANCADO	321	t	f
6283	317	91	BASICO	318	t	f
6284	317	92	BASICO	318	t	f
6285	317	93	BASICO	318	t	f
6286	317	94	AVANCADO	321	t	f
6287	317	95	BASICO	318	t	f
6288	317	96	BASICO	318	t	f
6289	317	97	BASICO	318	t	f
6290	317	130	BASICO	318	t	f
6291	317	113	AVANCADO	321	t	f
6292	317	114	AVANCADO	321	t	f
6293	317	115	AVANCADO	321	t	f
6294	317	116	INTERMEDIARIO	320	t	f
6295	317	117	AVANCADO	321	t	f
6296	317	118	AVANCADO	321	t	f
6297	317	119	AVANCADO	321	t	f
6298	317	120	AVANCADO	321	t	f
6299	317	121	BASICO	318	t	f
6300	317	122	BASICO	318	t	f
6301	317	123	BASICO	318	t	f
6302	317	124	AVANCADO	321	t	f
6303	317	125	BASICO	318	t	f
6304	317	126	BASICO	318	t	f
6305	317	127	BASICO	318	t	f
6306	317	129	AVANCADO	321	t	f
6307	317	1	AVANCADO	321	t	f
6308	317	2	BASICO	318	t	f
6309	317	3	BASICO	318	t	f
6310	317	4	AVANCADO	321	t	f
6311	317	5	AVANCADO	321	t	f
6312	317	6	BASICO	318	t	f
6313	317	7	INTERMEDIARIO	320	t	f
6314	317	8	AVANCADO	321	t	f
6315	317	9	AVANCADO	321	t	f
6316	317	10	AVANCADO	321	t	f
6317	317	11	AVANCADO	321	t	f
6318	317	12	AVANCADO	321	t	f
6319	317	63	INTERMEDIARIO	320	t	f
6320	317	64	INTERMEDIARIO	320	t	f
6321	317	65	AVANCADO	321	t	f
6322	317	66	AVANCADO	321	t	f
6323	317	67	INTERMEDIARIO	320	t	f
6324	317	68	INTERMEDIARIO	320	t	f
6325	317	69	BASICO	318	t	f
6326	317	70	BASICO	318	t	f
6327	317	71	BASICO	318	t	f
6328	317	72	AVANCADO	321	t	f
6329	317	73	INTERMEDIARIO	320	t	f
6330	317	74	INTERMEDIARIO	320	t	f
6331	317	75	AVANCADO	321	t	f
6332	317	76	AVANCADO	321	t	f
6333	317	77	BASICO	318	t	f
6334	317	78	BASICO	318	t	f
6335	317	79	BASICO	318	t	f
6336	317	81	BASICO	318	t	f
6337	317	82	AVANCADO	321	t	f
6338	317	108	AVANCADO	321	t	f
6339	317	109	AVANCADO	321	t	f
6340	317	110	AVANCADO	321	t	f
6341	317	111	AVANCADO	321	t	f
6342	317	112	INTERMEDIARIO	320	t	f
6343	92	63	BASICO	318	t	f
6344	92	68	BASICO	318	t	f
6345	92	72	BASICO	318	t	f
6346	92	108	INTERMEDIARIO	320	t	f
6347	92	109	BASICO	318	t	f
6348	210	98	BASICO	318	t	f
6349	210	99	BASICO	318	t	f
6350	210	100	BASICO	318	t	f
6351	210	101	BASICO	318	t	f
6352	210	102	INTERMEDIARIO	320	t	f
6353	210	103	INTERMEDIARIO	320	t	f
6354	210	104	INTERMEDIARIO	320	t	f
6355	210	105	INTERMEDIARIO	320	t	f
6356	210	106	INTERMEDIARIO	320	t	f
6357	210	107	INTERMEDIARIO	320	t	f
6358	210	47	BASICO	318	t	f
6359	210	48	INTERMEDIARIO	320	t	f
6360	210	49	INTERMEDIARIO	320	t	f
6361	210	50	INTERMEDIARIO	320	t	f
6362	210	51	INTERMEDIARIO	320	t	f
6363	210	52	INTERMEDIARIO	320	t	f
6364	210	28	BASICO	318	t	f
6365	210	29	INTERMEDIARIO	320	t	f
6366	210	30	INTERMEDIARIO	320	t	f
6367	210	31	BASICO	318	t	f
6368	210	32	BASICO	318	t	f
6369	210	33	INTERMEDIARIO	320	t	f
6370	210	34	INTERMEDIARIO	320	t	f
6371	210	35	INTERMEDIARIO	320	t	f
6372	210	36	INTERMEDIARIO	320	t	f
6373	210	37	INTERMEDIARIO	320	t	f
6374	210	38	INTERMEDIARIO	320	t	f
6375	210	39	BASICO	318	t	f
6376	210	40	INTERMEDIARIO	320	t	f
6377	210	41	INTERMEDIARIO	320	t	f
6378	210	42	INTERMEDIARIO	320	t	f
6379	210	43	INTERMEDIARIO	320	t	f
6380	210	44	INTERMEDIARIO	320	t	f
6381	210	45	BASICO	318	t	f
6382	210	46	BASICO	318	t	f
6383	210	13	INTERMEDIARIO	320	t	f
6384	210	14	INTERMEDIARIO	320	t	f
6385	210	15	INTERMEDIARIO	320	t	f
6386	210	16	INTERMEDIARIO	320	t	f
6387	210	17	INTERMEDIARIO	320	t	f
6388	210	18	INTERMEDIARIO	320	t	f
6389	210	19	INTERMEDIARIO	320	t	f
6390	210	20	INTERMEDIARIO	320	t	f
6391	210	21	INTERMEDIARIO	320	t	f
6392	210	22	INTERMEDIARIO	320	t	f
6393	210	23	BASICO	318	t	f
6394	210	24	BASICO	318	t	f
6395	210	25	BASICO	318	t	f
6396	210	26	INTERMEDIARIO	320	t	f
6397	210	27	BASICO	318	t	f
6398	210	53	INTERMEDIARIO	320	t	f
6399	210	54	INTERMEDIARIO	320	t	f
6400	210	55	AVANCADO	321	t	f
6401	210	56	AVANCADO	321	t	f
6402	210	57	BASICO	318	t	f
6403	210	58	AVANCADO	321	t	f
6404	210	59	INTERMEDIARIO	320	t	f
6405	210	60	INTERMEDIARIO	320	t	f
6406	210	61	INTERMEDIARIO	320	t	f
6407	210	62	INTERMEDIARIO	320	t	f
6408	210	83	BASICO	318	t	f
6409	210	84	INTERMEDIARIO	320	t	f
6410	210	85	BASICO	318	t	f
6411	210	86	BASICO	318	t	f
6412	210	87	INTERMEDIARIO	320	t	f
6413	210	88	BASICO	318	t	f
6414	210	89	BASICO	318	t	f
6415	210	90	BASICO	318	t	f
6416	210	91	BASICO	318	t	f
6417	210	92	BASICO	318	t	f
6418	210	93	INTERMEDIARIO	320	t	f
6419	210	94	INTERMEDIARIO	320	t	f
6420	210	95	BASICO	318	t	f
6421	210	96	BASICO	318	t	f
6422	210	97	BASICO	318	t	f
6423	210	130	BASICO	318	t	f
6424	210	113	INTERMEDIARIO	320	t	f
6425	210	114	INTERMEDIARIO	320	t	f
6426	210	115	INTERMEDIARIO	320	t	f
6427	210	116	INTERMEDIARIO	320	t	f
6428	210	117	INTERMEDIARIO	320	t	f
6429	210	118	INTERMEDIARIO	320	t	f
6430	210	119	INTERMEDIARIO	320	t	f
6431	210	120	INTERMEDIARIO	320	t	f
6432	210	121	BASICO	318	t	f
6433	210	122	INTERMEDIARIO	320	t	f
6434	210	123	INTERMEDIARIO	320	t	f
6435	210	124	INTERMEDIARIO	320	t	f
6436	210	125	BASICO	318	t	f
6437	210	126	BASICO	318	t	f
6438	210	127	INTERMEDIARIO	320	t	f
6439	210	129	INTERMEDIARIO	320	t	f
6440	210	1	INTERMEDIARIO	320	t	f
6441	210	2	BASICO	318	t	f
6442	210	3	INTERMEDIARIO	320	t	f
6443	210	4	INTERMEDIARIO	320	t	f
6444	210	5	BASICO	318	t	f
6445	210	6	BASICO	318	t	f
6446	210	7	INTERMEDIARIO	320	t	f
6447	210	8	INTERMEDIARIO	320	t	f
6448	210	9	INTERMEDIARIO	320	t	f
6449	210	10	INTERMEDIARIO	320	t	f
6450	210	11	INTERMEDIARIO	320	t	f
6451	210	12	INTERMEDIARIO	320	t	f
6452	210	63	INTERMEDIARIO	320	t	f
6453	210	64	BASICO	318	t	f
6454	210	65	INTERMEDIARIO	320	t	f
6455	210	66	INTERMEDIARIO	320	t	f
6456	210	67	INTERMEDIARIO	320	t	f
6457	210	68	INTERMEDIARIO	320	t	f
6458	210	69	BASICO	318	t	f
6459	210	70	BASICO	318	t	f
6460	210	71	INTERMEDIARIO	320	t	f
6461	210	72	INTERMEDIARIO	320	t	f
6462	210	73	INTERMEDIARIO	320	t	f
6463	210	74	INTERMEDIARIO	320	t	f
6464	210	75	INTERMEDIARIO	320	t	f
6465	210	76	INTERMEDIARIO	320	t	f
6466	210	77	INTERMEDIARIO	320	t	f
6467	210	78	INTERMEDIARIO	320	t	f
6468	210	79	INTERMEDIARIO	320	t	f
6469	210	81	BASICO	318	t	f
6470	210	82	INTERMEDIARIO	320	t	f
6471	210	108	INTERMEDIARIO	320	t	f
6472	210	109	INTERMEDIARIO	320	t	f
6473	210	110	INTERMEDIARIO	320	t	f
6474	210	111	INTERMEDIARIO	320	t	f
6475	210	112	INTERMEDIARIO	320	t	f
6476	123	98	BASICO	318	t	f
6477	123	99	BASICO	318	t	f
6478	123	100	BASICO	318	t	f
6479	123	101	BASICO	318	t	f
6480	123	102	BASICO	318	t	f
6481	123	103	BASICO	318	t	f
6482	123	104	BASICO	318	t	f
6483	123	105	BASICO	318	t	f
6484	123	106	INTERMEDIARIO	320	t	f
6485	123	107	INTERMEDIARIO	320	t	f
6486	123	47	BASICO	318	t	f
6487	123	48	BASICO	318	t	f
6488	123	49	BASICO	318	t	f
6489	123	50	BASICO	318	t	f
6490	123	51	BASICO	318	t	f
6491	123	52	BASICO	318	t	f
6492	123	28	BASICO	318	t	f
6493	123	29	INTERMEDIARIO	320	t	f
6494	123	30	BASICO	318	t	f
6495	123	31	BASICO	318	t	f
6496	123	32	BASICO	318	t	f
6497	123	33	BASICO	318	t	f
6498	123	34	BASICO	318	t	f
6499	123	35	BASICO	318	t	f
6500	123	36	INTERMEDIARIO	320	t	f
6501	123	37	BASICO	318	t	f
6502	123	38	BASICO	318	t	f
6503	123	39	BASICO	318	t	f
6504	123	40	BASICO	318	t	f
6505	123	41	INTERMEDIARIO	320	t	f
6506	123	42	BASICO	318	t	f
6507	123	43	AVANCADO	321	t	f
6508	123	44	BASICO	318	t	f
6509	123	45	BASICO	318	t	f
6510	123	46	BASICO	318	t	f
6511	123	13	BASICO	318	t	f
6512	123	14	BASICO	318	t	f
6513	123	15	BASICO	318	t	f
6514	123	16	BASICO	318	t	f
6515	123	17	BASICO	318	t	f
6516	123	18	INTERMEDIARIO	320	t	f
6517	123	19	INTERMEDIARIO	320	t	f
6518	123	20	INTERMEDIARIO	320	t	f
6519	123	21	INTERMEDIARIO	320	t	f
6520	123	22	BASICO	318	t	f
6521	123	23	BASICO	318	t	f
6522	123	24	BASICO	318	t	f
6523	123	25	BASICO	318	t	f
6524	123	26	BASICO	318	t	f
6525	123	27	BASICO	318	t	f
6526	123	53	BASICO	318	t	f
6527	123	54	BASICO	318	t	f
6528	123	55	INTERMEDIARIO	320	t	f
6529	123	56	INTERMEDIARIO	320	t	f
6530	123	57	BASICO	318	t	f
6531	123	58	INTERMEDIARIO	320	t	f
6532	123	59	BASICO	318	t	f
6533	123	60	BASICO	318	t	f
6534	123	61	INTERMEDIARIO	320	t	f
6535	123	62	INTERMEDIARIO	320	t	f
6536	123	83	BASICO	318	t	f
6537	123	84	BASICO	318	t	f
6538	123	85	BASICO	318	t	f
6539	123	86	BASICO	318	t	f
6540	123	87	BASICO	318	t	f
6541	123	88	BASICO	318	t	f
6542	123	89	BASICO	318	t	f
6543	123	90	BASICO	318	t	f
6544	123	91	BASICO	318	t	f
6545	123	92	BASICO	318	t	f
6546	123	93	BASICO	318	t	f
6547	123	94	BASICO	318	t	f
6548	123	95	BASICO	318	t	f
6549	123	96	BASICO	318	t	f
6550	123	97	BASICO	318	t	f
6551	123	130	BASICO	318	t	f
6552	123	113	INTERMEDIARIO	320	t	f
6553	123	114	BASICO	318	t	f
6554	123	115	INTERMEDIARIO	320	t	f
6555	123	116	INTERMEDIARIO	320	t	f
6556	123	117	INTERMEDIARIO	320	t	f
6557	123	118	BASICO	318	t	f
6558	123	119	INTERMEDIARIO	320	t	f
6559	123	120	BASICO	318	t	f
6560	123	121	BASICO	318	t	f
6561	123	122	BASICO	318	t	f
6562	123	123	BASICO	318	t	f
6563	123	124	INTERMEDIARIO	320	t	f
6564	123	125	BASICO	318	t	f
6565	123	126	BASICO	318	t	f
6566	123	127	BASICO	318	t	f
6567	123	129	INTERMEDIARIO	320	t	f
6568	123	1	INTERMEDIARIO	320	t	f
6569	123	2	BASICO	318	t	f
6570	123	3	BASICO	318	t	f
6571	123	4	BASICO	318	t	f
6572	123	5	BASICO	318	t	f
6573	123	6	BASICO	318	t	f
6574	123	7	BASICO	318	t	f
6575	123	8	INTERMEDIARIO	320	t	f
6576	123	9	INTERMEDIARIO	320	t	f
6577	123	10	BASICO	318	t	f
6578	123	11	INTERMEDIARIO	320	t	f
6579	123	12	INTERMEDIARIO	320	t	f
6580	123	63	BASICO	318	t	f
6581	123	64	BASICO	318	t	f
6582	123	65	INTERMEDIARIO	320	t	f
6583	123	66	INTERMEDIARIO	320	t	f
6584	123	67	BASICO	318	t	f
6585	123	68	BASICO	318	t	f
6586	123	69	BASICO	318	t	f
6587	123	70	BASICO	318	t	f
6588	123	71	BASICO	318	t	f
6589	123	72	INTERMEDIARIO	320	t	f
6590	123	73	BASICO	318	t	f
6591	123	74	BASICO	318	t	f
6592	123	75	INTERMEDIARIO	320	t	f
6593	123	76	INTERMEDIARIO	320	t	f
6594	123	77	BASICO	318	t	f
6595	123	78	BASICO	318	t	f
6596	123	79	BASICO	318	t	f
6597	123	81	BASICO	318	t	f
6598	123	82	INTERMEDIARIO	320	t	f
6599	123	108	INTERMEDIARIO	320	t	f
6600	123	109	BASICO	318	t	f
6601	123	110	BASICO	318	t	f
6602	123	111	BASICO	318	t	f
6603	123	112	BASICO	318	t	f
6604	34	98	BASICO	318	t	f
6605	34	99	INTERMEDIARIO	320	t	f
6606	34	100	INTERMEDIARIO	320	t	f
6607	34	101	BASICO	318	t	f
6608	34	102	BASICO	318	t	f
6609	34	103	BASICO	318	t	f
6610	34	104	INTERMEDIARIO	320	t	f
6611	34	105	BASICO	318	t	f
6612	34	106	INTERMEDIARIO	320	t	f
6613	34	107	INTERMEDIARIO	320	t	f
6614	34	47	BASICO	318	t	f
6615	34	48	INTERMEDIARIO	320	t	f
6616	34	49	INTERMEDIARIO	320	t	f
6617	34	50	BASICO	318	t	f
6618	34	51	INTERMEDIARIO	320	t	f
6619	34	52	BASICO	318	t	f
6620	34	28	BASICO	318	t	f
6621	34	29	BASICO	318	t	f
6622	34	30	BASICO	318	t	f
6623	34	31	BASICO	318	t	f
6624	34	32	BASICO	318	t	f
6625	34	33	BASICO	318	t	f
6626	34	34	BASICO	318	t	f
6627	34	35	INTERMEDIARIO	320	t	f
6628	34	36	INTERMEDIARIO	320	t	f
6629	34	37	INTERMEDIARIO	320	t	f
6630	34	38	INTERMEDIARIO	320	t	f
6631	34	39	BASICO	318	t	f
6632	34	40	BASICO	318	t	f
6633	34	41	BASICO	318	t	f
6634	34	42	BASICO	318	t	f
6635	34	43	BASICO	318	t	f
6636	34	44	BASICO	318	t	f
6637	34	45	BASICO	318	t	f
6638	34	46	BASICO	318	t	f
6639	34	13	BASICO	318	t	f
6640	34	14	BASICO	318	t	f
6641	34	15	BASICO	318	t	f
6642	34	16	BASICO	318	t	f
6643	34	17	BASICO	318	t	f
6644	34	18	BASICO	318	t	f
6645	34	19	BASICO	318	t	f
6646	34	20	BASICO	318	t	f
6647	34	21	BASICO	318	t	f
6648	34	22	BASICO	318	t	f
6649	34	23	BASICO	318	t	f
6650	34	24	BASICO	318	t	f
6651	34	25	BASICO	318	t	f
6652	34	26	BASICO	318	t	f
6653	34	27	BASICO	318	t	f
6654	34	53	BASICO	318	t	f
6655	34	54	BASICO	318	t	f
6656	34	55	BASICO	318	t	f
6657	34	56	BASICO	318	t	f
6658	34	57	BASICO	318	t	f
6659	34	58	BASICO	318	t	f
6660	34	59	BASICO	318	t	f
6661	34	60	BASICO	318	t	f
6662	34	61	BASICO	318	t	f
6663	34	62	BASICO	318	t	f
6664	34	83	BASICO	318	t	f
6665	34	84	BASICO	318	t	f
6666	34	85	BASICO	318	t	f
6667	34	86	BASICO	318	t	f
6668	34	87	BASICO	318	t	f
6669	34	88	BASICO	318	t	f
6670	34	89	BASICO	318	t	f
6671	34	90	BASICO	318	t	f
6672	34	91	BASICO	318	t	f
6673	34	92	BASICO	318	t	f
6674	34	93	BASICO	318	t	f
6675	34	94	BASICO	318	t	f
6676	34	95	BASICO	318	t	f
6677	34	96	BASICO	318	t	f
6678	34	97	BASICO	318	t	f
6679	34	130	BASICO	318	t	f
6680	34	113	BASICO	318	t	f
6681	34	114	BASICO	318	t	f
6682	34	115	INTERMEDIARIO	320	t	f
6683	34	116	BASICO	318	t	f
6684	34	117	INTERMEDIARIO	320	t	f
6685	34	118	BASICO	318	t	f
6686	34	119	INTERMEDIARIO	320	t	f
6687	34	120	BASICO	318	t	f
6688	34	121	BASICO	318	t	f
6689	34	122	BASICO	318	t	f
6690	34	123	BASICO	318	t	f
6691	34	124	BASICO	318	t	f
6692	34	125	BASICO	318	t	f
6693	34	126	BASICO	318	t	f
6694	34	127	BASICO	318	t	f
6695	34	129	BASICO	318	t	f
6696	34	1	BASICO	318	t	f
6697	34	2	INTERMEDIARIO	320	t	f
6698	34	3	BASICO	318	t	f
6699	34	4	BASICO	318	t	f
6700	34	5	BASICO	318	t	f
6701	34	6	BASICO	318	t	f
6702	34	7	BASICO	318	t	f
6703	34	8	BASICO	318	t	f
6704	34	9	BASICO	318	t	f
6705	34	10	BASICO	318	t	f
6706	34	11	INTERMEDIARIO	320	t	f
6707	34	12	INTERMEDIARIO	320	t	f
6708	34	63	BASICO	318	t	f
6709	34	64	BASICO	318	t	f
6710	34	65	BASICO	318	t	f
6711	34	66	BASICO	318	t	f
6712	34	67	BASICO	318	t	f
6713	34	68	BASICO	318	t	f
6714	34	69	BASICO	318	t	f
6715	34	70	BASICO	318	t	f
6716	34	71	BASICO	318	t	f
6717	34	72	INTERMEDIARIO	320	t	f
6718	34	73	BASICO	318	t	f
6719	34	74	BASICO	318	t	f
6720	34	75	BASICO	318	t	f
6721	34	76	BASICO	318	t	f
6722	34	77	BASICO	318	t	f
6723	34	78	BASICO	318	t	f
6724	34	79	BASICO	318	t	f
6725	34	81	BASICO	318	t	f
6726	34	82	INTERMEDIARIO	320	t	f
6727	34	108	BASICO	318	t	f
6728	34	109	BASICO	318	t	f
6729	34	110	BASICO	318	t	f
6730	34	111	BASICO	318	t	f
6731	34	112	BASICO	318	t	f
6732	309	102	INTERMEDIARIO	320	t	f
6733	309	104	INTERMEDIARIO	320	t	f
6734	309	106	AVANCADO	321	t	f
6735	309	107	AVANCADO	321	t	f
6736	309	47	INTERMEDIARIO	320	t	f
6737	309	49	AVANCADO	321	t	f
6738	309	50	INTERMEDIARIO	320	t	f
6739	309	51	AVANCADO	321	t	f
6740	309	52	INTERMEDIARIO	320	t	f
6741	309	29	INTERMEDIARIO	320	t	f
6742	309	30	BASICO	318	t	f
6743	309	33	BASICO	318	t	f
6744	309	34	INTERMEDIARIO	320	t	f
6745	309	36	INTERMEDIARIO	320	t	f
6746	309	37	INTERMEDIARIO	320	t	f
6747	309	38	INTERMEDIARIO	320	t	f
6748	309	40	INTERMEDIARIO	320	t	f
6749	309	41	INTERMEDIARIO	320	t	f
6750	309	43	INTERMEDIARIO	320	t	f
6751	309	44	INTERMEDIARIO	320	t	f
6752	309	14	INTERMEDIARIO	320	t	f
6753	309	16	INTERMEDIARIO	320	t	f
6754	309	17	INTERMEDIARIO	320	t	f
6755	309	18	BASICO	318	t	f
6756	309	19	BASICO	318	t	f
6757	309	20	BASICO	318	t	f
6758	309	21	AVANCADO	321	t	f
6759	309	22	INTERMEDIARIO	320	t	f
6760	309	26	INTERMEDIARIO	320	t	f
6761	309	27	INTERMEDIARIO	320	t	f
6762	309	53	INTERMEDIARIO	320	t	f
6763	309	55	INTERMEDIARIO	320	t	f
6764	309	56	INTERMEDIARIO	320	t	f
6765	309	58	BASICO	318	t	f
6766	309	59	INTERMEDIARIO	320	t	f
6767	309	60	BASICO	318	t	f
6768	309	61	BASICO	318	t	f
6769	309	84	BASICO	318	t	f
6770	309	94	INTERMEDIARIO	320	t	f
6771	309	113	BASICO	318	t	f
6772	309	114	BASICO	318	t	f
6773	309	115	AVANCADO	321	t	f
6774	309	116	BASICO	318	t	f
6775	309	117	AVANCADO	321	t	f
6776	309	118	INTERMEDIARIO	320	t	f
6777	309	119	INTERMEDIARIO	320	t	f
6778	309	124	BASICO	318	t	f
6779	309	129	INTERMEDIARIO	320	t	f
6780	309	1	INTERMEDIARIO	320	t	f
6781	309	8	INTERMEDIARIO	320	t	f
6782	309	9	INTERMEDIARIO	320	t	f
6783	309	11	AVANCADO	321	t	f
6784	309	12	AVANCADO	321	t	f
6785	309	65	INTERMEDIARIO	320	t	f
6786	309	66	INTERMEDIARIO	320	t	f
6787	309	72	INTERMEDIARIO	320	t	f
6788	309	75	BASICO	318	t	f
6789	309	82	INTERMEDIARIO	320	t	f
6790	309	108	BASICO	318	t	f
6791	309	109	BASICO	318	t	f
6792	309	110	BASICO	318	t	f
6793	287	98	BASICO	318	t	f
6794	287	99	BASICO	318	t	f
6795	287	100	INTERMEDIARIO	320	t	f
6796	287	101	BASICO	318	t	f
6797	287	102	INTERMEDIARIO	320	t	f
6798	287	103	INTERMEDIARIO	320	t	f
6799	287	104	BASICO	318	t	f
6800	287	105	BASICO	318	t	f
6801	287	106	INTERMEDIARIO	320	t	f
6802	287	107	INTERMEDIARIO	320	t	f
6803	287	47	BASICO	318	t	f
6804	287	48	BASICO	318	t	f
6805	287	49	INTERMEDIARIO	320	t	f
6806	287	50	BASICO	318	t	f
6807	287	51	BASICO	318	t	f
6808	287	52	INTERMEDIARIO	320	t	f
6809	287	28	BASICO	318	t	f
6810	287	29	INTERMEDIARIO	320	t	f
6811	287	30	BASICO	318	t	f
6812	287	31	BASICO	318	t	f
6813	287	32	BASICO	318	t	f
6814	287	33	BASICO	318	t	f
6815	287	34	BASICO	318	t	f
6816	287	36	INTERMEDIARIO	320	t	f
6817	287	37	INTERMEDIARIO	320	t	f
6818	287	38	BASICO	318	t	f
6819	287	39	INTERMEDIARIO	320	t	f
6820	287	40	AVANCADO	321	t	f
6821	287	42	INTERMEDIARIO	320	t	f
6822	287	44	AVANCADO	321	t	f
6823	287	45	BASICO	318	t	f
6824	287	46	BASICO	318	t	f
6825	287	13	BASICO	318	t	f
6826	287	15	INTERMEDIARIO	320	t	f
6827	287	16	BASICO	318	t	f
6828	287	17	BASICO	318	t	f
6829	287	18	INTERMEDIARIO	320	t	f
6830	287	19	INTERMEDIARIO	320	t	f
6831	287	20	INTERMEDIARIO	320	t	f
6832	287	22	BASICO	318	t	f
6833	287	23	BASICO	318	t	f
6834	287	24	BASICO	318	t	f
6835	287	25	BASICO	318	t	f
6836	287	26	BASICO	318	t	f
6837	287	27	BASICO	318	t	f
6838	287	53	BASICO	318	t	f
6839	287	54	BASICO	318	t	f
6840	287	56	INTERMEDIARIO	320	t	f
6841	287	57	BASICO	318	t	f
6842	287	58	INTERMEDIARIO	320	t	f
6843	287	62	INTERMEDIARIO	320	t	f
6844	287	83	BASICO	318	t	f
6845	287	84	BASICO	318	t	f
6846	287	85	INTERMEDIARIO	320	t	f
6847	287	86	BASICO	318	t	f
6848	287	87	BASICO	318	t	f
6849	287	88	BASICO	318	t	f
6850	287	89	AVANCADO	321	t	f
6851	287	90	BASICO	318	t	f
6852	287	91	BASICO	318	t	f
6853	287	92	BASICO	318	t	f
6854	287	93	BASICO	318	t	f
6855	287	94	AVANCADO	321	t	f
6856	287	95	BASICO	318	t	f
6857	287	96	BASICO	318	t	f
6858	287	97	BASICO	318	t	f
6859	287	130	BASICO	318	t	f
6860	287	113	INTERMEDIARIO	320	t	f
6861	287	116	INTERMEDIARIO	320	t	f
6862	287	121	BASICO	318	t	f
6863	287	122	INTERMEDIARIO	320	t	f
6864	287	123	BASICO	318	t	f
6865	287	124	BASICO	318	t	f
6866	287	125	BASICO	318	t	f
6867	287	126	BASICO	318	t	f
6868	287	127	BASICO	318	t	f
6869	287	129	AVANCADO	321	t	f
6870	287	1	AVANCADO	321	t	f
6871	287	2	INTERMEDIARIO	320	t	f
6872	287	3	INTERMEDIARIO	320	t	f
6873	287	4	AVANCADO	321	t	f
6874	287	5	INTERMEDIARIO	320	t	f
6875	287	6	INTERMEDIARIO	320	t	f
6876	287	7	AVANCADO	321	t	f
6877	287	8	AVANCADO	321	t	f
6878	287	9	AVANCADO	321	t	f
6879	287	10	INTERMEDIARIO	320	t	f
6880	287	11	INTERMEDIARIO	320	t	f
6881	287	12	INTERMEDIARIO	320	t	f
6882	287	63	INTERMEDIARIO	320	t	f
6883	287	64	BASICO	318	t	f
6884	287	66	AVANCADO	321	t	f
6885	287	67	INTERMEDIARIO	320	t	f
6886	287	68	INTERMEDIARIO	320	t	f
6887	287	69	INTERMEDIARIO	320	t	f
6888	287	70	BASICO	318	t	f
6889	287	71	BASICO	318	t	f
6890	287	73	INTERMEDIARIO	320	t	f
6891	287	74	INTERMEDIARIO	320	t	f
6892	287	75	BASICO	318	t	f
6893	287	76	INTERMEDIARIO	320	t	f
6894	287	77	BASICO	318	t	f
6895	287	78	BASICO	318	t	f
6896	287	79	BASICO	318	t	f
6897	287	81	BASICO	318	t	f
6898	287	82	BASICO	318	t	f
6899	287	108	AVANCADO	321	t	f
6900	287	109	AVANCADO	321	t	f
6901	287	110	BASICO	318	t	f
6902	287	111	AVANCADO	321	t	f
6903	287	112	BASICO	318	t	f
6904	159	98	BASICO	318	t	f
6905	159	99	BASICO	318	t	f
6906	159	100	BASICO	318	t	f
6907	159	101	BASICO	318	t	f
6908	159	102	INTERMEDIARIO	320	t	f
6909	159	103	BASICO	318	t	f
6910	159	104	BASICO	318	t	f
6911	159	105	INTERMEDIARIO	320	t	f
6912	159	106	AVANCADO	321	t	f
6913	159	107	BASICO	318	t	f
6914	159	47	BASICO	318	t	f
6915	159	48	BASICO	318	t	f
6916	159	49	BASICO	318	t	f
6917	159	50	INTERMEDIARIO	320	t	f
6918	159	51	BASICO	318	t	f
6919	159	52	BASICO	318	t	f
6920	159	29	BASICO	318	t	f
6921	159	38	BASICO	318	t	f
6922	159	18	BASICO	318	t	f
6923	159	56	BASICO	318	t	f
6924	159	58	BASICO	318	t	f
6925	159	62	BASICO	318	t	f
6926	54	98	BASICO	318	t	f
6927	54	99	BASICO	318	t	f
6928	54	100	BASICO	318	t	f
6929	54	101	BASICO	318	t	f
6930	54	102	BASICO	318	t	f
6931	54	103	BASICO	318	t	f
6932	54	104	BASICO	318	t	f
6933	54	105	BASICO	318	t	f
6934	54	106	BASICO	318	t	f
6935	54	107	BASICO	318	t	f
6936	54	47	BASICO	318	t	f
6937	54	48	BASICO	318	t	f
6938	54	49	BASICO	318	t	f
6939	54	50	BASICO	318	t	f
6940	54	51	BASICO	318	t	f
6941	54	52	BASICO	318	t	f
6942	54	28	BASICO	318	t	f
6943	54	29	BASICO	318	t	f
6944	54	30	BASICO	318	t	f
6945	54	31	BASICO	318	t	f
6946	54	32	BASICO	318	t	f
6947	54	33	BASICO	318	t	f
6948	54	34	BASICO	318	t	f
6949	54	35	BASICO	318	t	f
6950	54	36	BASICO	318	t	f
6951	54	37	BASICO	318	t	f
6952	54	38	BASICO	318	t	f
6953	54	39	BASICO	318	t	f
6954	54	40	BASICO	318	t	f
6955	54	41	BASICO	318	t	f
6956	54	42	BASICO	318	t	f
6957	54	43	BASICO	318	t	f
6958	54	44	BASICO	318	t	f
6959	54	45	BASICO	318	t	f
6960	54	46	BASICO	318	t	f
6961	54	13	BASICO	318	t	f
6962	54	14	BASICO	318	t	f
6963	54	15	BASICO	318	t	f
6964	54	16	BASICO	318	t	f
6965	54	17	BASICO	318	t	f
6966	54	18	BASICO	318	t	f
6967	54	19	BASICO	318	t	f
6968	54	20	BASICO	318	t	f
6969	54	21	BASICO	318	t	f
6970	54	22	BASICO	318	t	f
6971	54	23	BASICO	318	t	f
6972	54	24	BASICO	318	t	f
6973	54	25	BASICO	318	t	f
6974	54	26	BASICO	318	t	f
6975	54	27	BASICO	318	t	f
6976	54	53	BASICO	318	t	f
6977	54	54	BASICO	318	t	f
6978	54	55	BASICO	318	t	f
6979	54	56	BASICO	318	t	f
6980	54	57	BASICO	318	t	f
6981	54	58	BASICO	318	t	f
6982	54	60	BASICO	318	t	f
6983	54	61	BASICO	318	t	f
6984	54	62	BASICO	318	t	f
6985	54	83	BASICO	318	t	f
6986	54	84	BASICO	318	t	f
6987	54	85	BASICO	318	t	f
6988	54	86	BASICO	318	t	f
6989	54	87	BASICO	318	t	f
6990	54	88	BASICO	318	t	f
6991	54	89	BASICO	318	t	f
6992	54	90	BASICO	318	t	f
6993	54	91	BASICO	318	t	f
6994	54	92	BASICO	318	t	f
6995	54	93	BASICO	318	t	f
6996	54	94	BASICO	318	t	f
6997	54	95	BASICO	318	t	f
6998	54	96	BASICO	318	t	f
6999	54	97	BASICO	318	t	f
7000	54	130	BASICO	318	t	f
7001	54	113	BASICO	318	t	f
7002	54	114	BASICO	318	t	f
7003	54	115	BASICO	318	t	f
7004	54	116	BASICO	318	t	f
7005	54	117	BASICO	318	t	f
7006	54	118	BASICO	318	t	f
7007	54	119	BASICO	318	t	f
7008	54	120	BASICO	318	t	f
7009	54	121	BASICO	318	t	f
7010	54	122	BASICO	318	t	f
7011	54	123	BASICO	318	t	f
7012	54	124	BASICO	318	t	f
7013	54	125	BASICO	318	t	f
7014	54	126	BASICO	318	t	f
7015	54	127	BASICO	318	t	f
7016	54	129	BASICO	318	t	f
7017	54	1	BASICO	318	t	f
7018	54	2	BASICO	318	t	f
7019	54	3	BASICO	318	t	f
7020	54	4	BASICO	318	t	f
7021	54	5	BASICO	318	t	f
7022	54	6	BASICO	318	t	f
7023	54	7	BASICO	318	t	f
7024	54	8	BASICO	318	t	f
7025	54	9	BASICO	318	t	f
7026	54	10	BASICO	318	t	f
7027	54	12	BASICO	318	t	f
7028	54	63	BASICO	318	t	f
7029	54	64	BASICO	318	t	f
7030	54	65	BASICO	318	t	f
7031	54	66	BASICO	318	t	f
7032	54	67	BASICO	318	t	f
7033	54	68	BASICO	318	t	f
7034	54	69	BASICO	318	t	f
7035	54	70	BASICO	318	t	f
7036	54	71	BASICO	318	t	f
7037	54	72	BASICO	318	t	f
7038	54	73	BASICO	318	t	f
7039	54	74	BASICO	318	t	f
7040	54	75	BASICO	318	t	f
7041	54	76	BASICO	318	t	f
7042	54	77	BASICO	318	t	f
7043	54	78	BASICO	318	t	f
7044	54	79	BASICO	318	t	f
7045	54	81	BASICO	318	t	f
7046	54	82	BASICO	318	t	f
7047	54	108	BASICO	318	t	f
7048	54	109	BASICO	318	t	f
7049	54	110	BASICO	318	t	f
7050	54	111	BASICO	318	t	f
7051	54	112	BASICO	318	t	f
7052	265	98	INTERMEDIARIO	320	t	f
7053	265	99	BASICO	318	t	f
7054	265	100	BASICO	318	t	f
7055	265	101	INTERMEDIARIO	320	t	f
7056	265	103	BASICO	318	t	f
7057	265	104	INTERMEDIARIO	320	t	f
7058	265	105	INTERMEDIARIO	320	t	f
7059	265	107	INTERMEDIARIO	320	t	f
7060	265	47	BASICO	318	t	f
7061	265	48	BASICO	318	t	f
7062	265	49	AVANCADO	321	t	f
7063	265	51	BASICO	318	t	f
7064	265	52	AVANCADO	321	t	f
7065	265	29	AVANCADO	321	t	f
7066	265	31	BASICO	318	t	f
7067	265	32	BASICO	318	t	f
7068	265	33	INTERMEDIARIO	320	t	f
7069	265	35	AVANCADO	321	t	f
7070	265	37	AVANCADO	321	t	f
7071	265	39	INTERMEDIARIO	320	t	f
7072	265	40	AVANCADO	321	t	f
7073	265	42	AVANCADO	321	t	f
7074	265	43	AVANCADO	321	t	f
7075	265	44	BASICO	318	t	f
7076	265	45	BASICO	318	t	f
7077	265	46	BASICO	318	t	f
7078	265	13	BASICO	318	t	f
7079	265	14	INTERMEDIARIO	320	t	f
7080	265	15	BASICO	318	t	f
7081	265	17	BASICO	318	t	f
7082	265	21	INTERMEDIARIO	320	t	f
7083	265	22	BASICO	318	t	f
7084	265	23	AVANCADO	321	t	f
7085	265	24	BASICO	318	t	f
7086	265	25	BASICO	318	t	f
7087	265	27	BASICO	318	t	f
7088	265	54	AVANCADO	321	t	f
7089	265	55	AVANCADO	321	t	f
7090	265	56	AVANCADO	321	t	f
7091	265	58	AVANCADO	321	t	f
7092	265	59	INTERMEDIARIO	320	t	f
7093	265	60	INTERMEDIARIO	320	t	f
7094	265	61	AVANCADO	321	t	f
7095	265	83	BASICO	318	t	f
7096	265	85	INTERMEDIARIO	320	t	f
7097	265	86	INTERMEDIARIO	320	t	f
7098	265	87	BASICO	318	t	f
7099	265	88	BASICO	318	t	f
7100	265	89	INTERMEDIARIO	320	t	f
7101	265	90	BASICO	318	t	f
7102	265	91	BASICO	318	t	f
7103	265	93	BASICO	318	t	f
7104	265	94	INTERMEDIARIO	320	t	f
7105	265	95	BASICO	318	t	f
7106	265	96	BASICO	318	t	f
7107	265	97	AVANCADO	321	t	f
7108	265	130	BASICO	318	t	f
7109	265	113	INTERMEDIARIO	320	t	f
7110	265	114	INTERMEDIARIO	320	t	f
7111	265	115	INTERMEDIARIO	320	t	f
7112	265	116	INTERMEDIARIO	320	t	f
7113	265	117	INTERMEDIARIO	320	t	f
7114	265	118	INTERMEDIARIO	320	t	f
7115	265	120	INTERMEDIARIO	320	t	f
7116	265	121	BASICO	318	t	f
7117	265	122	INTERMEDIARIO	320	t	f
7118	265	123	INTERMEDIARIO	320	t	f
7119	265	124	INTERMEDIARIO	320	t	f
7120	265	125	BASICO	318	t	f
7121	265	126	INTERMEDIARIO	320	t	f
7122	265	127	BASICO	318	t	f
7123	265	129	AVANCADO	321	t	f
7124	265	1	AVANCADO	321	t	f
7125	265	2	AVANCADO	321	t	f
7126	265	3	BASICO	318	t	f
7127	265	4	AVANCADO	321	t	f
7128	265	5	AVANCADO	321	t	f
7129	265	6	BASICO	318	t	f
7130	265	9	AVANCADO	321	t	f
7131	265	10	BASICO	318	t	f
7132	265	11	BASICO	318	t	f
7133	265	12	AVANCADO	321	t	f
7134	265	63	BASICO	318	t	f
7135	265	64	BASICO	318	t	f
7136	265	65	AVANCADO	321	t	f
7137	265	66	AVANCADO	321	t	f
7138	265	67	INTERMEDIARIO	320	t	f
7139	265	68	BASICO	318	t	f
7140	265	69	BASICO	318	t	f
7141	265	70	BASICO	318	t	f
7142	265	71	INTERMEDIARIO	320	t	f
7143	265	72	INTERMEDIARIO	320	t	f
7144	265	73	BASICO	318	t	f
7145	265	74	BASICO	318	t	f
7146	265	75	BASICO	318	t	f
7147	265	76	BASICO	318	t	f
7148	265	77	BASICO	318	t	f
7149	265	78	BASICO	318	t	f
7150	265	79	BASICO	318	t	f
7151	265	81	BASICO	318	t	f
7152	265	82	INTERMEDIARIO	320	t	f
7153	265	108	AVANCADO	321	t	f
7154	265	109	AVANCADO	321	t	f
7155	265	110	AVANCADO	321	t	f
7156	265	111	AVANCADO	321	t	f
7157	265	112	AVANCADO	321	t	f
7158	289	98	BASICO	318	t	f
7159	289	99	BASICO	318	t	f
7160	289	100	BASICO	318	t	f
7161	289	101	BASICO	318	t	f
7162	289	102	BASICO	318	t	f
7163	289	103	BASICO	318	t	f
7164	289	104	BASICO	318	t	f
7165	289	105	BASICO	318	t	f
7166	289	106	INTERMEDIARIO	320	t	f
7167	289	107	BASICO	318	t	f
7168	289	47	BASICO	318	t	f
7169	289	48	BASICO	318	t	f
7170	289	49	BASICO	318	t	f
7171	289	50	BASICO	318	t	f
7172	289	51	BASICO	318	t	f
7173	289	52	BASICO	318	t	f
7174	289	28	BASICO	318	t	f
7175	289	29	BASICO	318	t	f
7176	289	30	BASICO	318	t	f
7177	289	31	BASICO	318	t	f
7178	289	32	BASICO	318	t	f
7179	289	33	BASICO	318	t	f
7180	289	34	BASICO	318	t	f
7181	289	35	BASICO	318	t	f
7182	289	36	BASICO	318	t	f
7183	289	37	INTERMEDIARIO	320	t	f
7184	289	38	BASICO	318	t	f
7185	289	39	BASICO	318	t	f
7186	289	40	BASICO	318	t	f
7187	289	41	BASICO	318	t	f
7188	289	42	BASICO	318	t	f
7189	289	43	BASICO	318	t	f
7190	289	44	BASICO	318	t	f
7191	289	45	BASICO	318	t	f
7192	289	46	BASICO	318	t	f
7193	289	13	BASICO	318	t	f
7194	289	14	BASICO	318	t	f
7195	289	15	BASICO	318	t	f
7196	289	16	BASICO	318	t	f
7197	289	17	BASICO	318	t	f
7198	289	18	BASICO	318	t	f
7199	289	19	BASICO	318	t	f
7200	289	20	BASICO	318	t	f
7201	289	21	BASICO	318	t	f
7202	289	22	BASICO	318	t	f
7203	289	23	BASICO	318	t	f
7204	289	24	BASICO	318	t	f
7205	289	25	BASICO	318	t	f
7206	289	26	BASICO	318	t	f
7207	289	27	BASICO	318	t	f
7208	289	53	BASICO	318	t	f
7209	289	54	BASICO	318	t	f
7210	289	55	BASICO	318	t	f
7211	289	56	BASICO	318	t	f
7212	289	57	BASICO	318	t	f
7213	289	58	BASICO	318	t	f
7214	289	59	BASICO	318	t	f
7215	289	60	BASICO	318	t	f
7216	289	61	BASICO	318	t	f
7217	289	62	BASICO	318	t	f
7218	289	83	BASICO	318	t	f
7219	289	84	BASICO	318	t	f
7220	289	85	BASICO	318	t	f
7221	289	86	BASICO	318	t	f
7222	289	87	BASICO	318	t	f
7223	289	88	BASICO	318	t	f
7224	289	89	BASICO	318	t	f
7225	289	90	BASICO	318	t	f
7226	289	91	BASICO	318	t	f
7227	289	92	BASICO	318	t	f
7228	289	93	BASICO	318	t	f
7229	289	94	BASICO	318	t	f
7230	289	95	BASICO	318	t	f
7231	289	96	BASICO	318	t	f
7232	289	97	BASICO	318	t	f
7233	289	130	BASICO	318	t	f
7234	289	113	BASICO	318	t	f
7235	289	114	BASICO	318	t	f
7236	289	115	BASICO	318	t	f
7237	289	116	BASICO	318	t	f
7238	289	117	BASICO	318	t	f
7239	289	118	BASICO	318	t	f
7240	289	119	BASICO	318	t	f
7241	289	120	BASICO	318	t	f
7242	289	121	BASICO	318	t	f
7243	289	122	BASICO	318	t	f
7244	289	123	BASICO	318	t	f
7245	289	124	BASICO	318	t	f
7246	289	125	BASICO	318	t	f
7247	289	126	BASICO	318	t	f
7248	289	127	BASICO	318	t	f
7249	289	129	BASICO	318	t	f
7250	289	1	BASICO	318	t	f
7251	289	2	BASICO	318	t	f
7252	289	3	BASICO	318	t	f
7253	289	4	BASICO	318	t	f
7254	289	5	BASICO	318	t	f
7255	289	6	BASICO	318	t	f
7256	289	7	BASICO	318	t	f
7257	289	8	BASICO	318	t	f
7258	289	9	BASICO	318	t	f
7259	289	10	BASICO	318	t	f
7260	289	11	BASICO	318	t	f
7261	289	12	BASICO	318	t	f
7262	289	63	BASICO	318	t	f
7263	289	64	BASICO	318	t	f
7264	289	65	BASICO	318	t	f
7265	289	66	BASICO	318	t	f
7266	289	67	BASICO	318	t	f
7267	289	68	BASICO	318	t	f
7268	289	69	BASICO	318	t	f
7269	289	70	BASICO	318	t	f
7270	289	71	BASICO	318	t	f
7271	289	72	BASICO	318	t	f
7272	289	73	BASICO	318	t	f
7273	289	74	BASICO	318	t	f
7274	289	75	BASICO	318	t	f
7275	289	76	BASICO	318	t	f
7276	289	77	BASICO	318	t	f
7277	289	78	BASICO	318	t	f
7278	289	79	BASICO	318	t	f
7279	289	81	BASICO	318	t	f
7280	289	82	BASICO	318	t	f
7281	289	108	BASICO	318	t	f
7282	289	109	BASICO	318	t	f
7283	289	110	BASICO	318	t	f
7284	289	111	BASICO	318	t	f
7285	289	112	BASICO	318	t	f
7286	197	106	INTERMEDIARIO	320	t	f
7287	197	30	BASICO	318	t	f
7288	197	21	BASICO	318	t	f
7289	197	55	BASICO	318	t	f
7290	197	56	BASICO	318	t	f
7291	197	58	BASICO	318	t	f
7292	197	113	BASICO	318	t	f
7293	197	114	BASICO	318	t	f
7294	197	115	BASICO	318	t	f
7295	197	116	BASICO	318	t	f
7296	197	117	BASICO	318	t	f
7297	197	118	BASICO	318	t	f
7298	197	119	BASICO	318	t	f
7299	197	121	BASICO	318	t	f
7300	197	123	BASICO	318	t	f
7301	197	124	BASICO	318	t	f
7302	197	125	BASICO	318	t	f
7303	197	126	BASICO	318	t	f
7304	197	127	BASICO	318	t	f
7305	197	129	INTERMEDIARIO	320	t	f
7306	197	63	BASICO	318	t	f
7307	197	64	BASICO	318	t	f
7308	197	65	BASICO	318	t	f
7309	197	68	INTERMEDIARIO	320	t	f
7310	197	70	BASICO	318	t	f
7311	197	71	BASICO	318	t	f
7312	197	72	INTERMEDIARIO	320	t	f
7313	197	73	BASICO	318	t	f
7314	197	75	INTERMEDIARIO	320	t	f
7315	197	76	BASICO	318	t	f
7316	197	77	BASICO	318	t	f
7317	197	78	BASICO	318	t	f
7318	197	82	INTERMEDIARIO	320	t	f
7319	197	112	BASICO	318	t	f
7320	293	98	INTERMEDIARIO	320	t	f
7321	293	99	BASICO	318	t	f
7322	293	100	BASICO	318	t	f
7323	293	102	BASICO	318	t	f
7324	293	103	AVANCADO	321	t	f
7325	293	104	BASICO	318	t	f
7326	293	105	BASICO	318	t	f
7327	293	106	AVANCADO	321	t	f
7328	293	107	AVANCADO	321	t	f
7329	293	47	INTERMEDIARIO	320	t	f
7330	293	48	BASICO	318	t	f
7331	293	50	INTERMEDIARIO	320	t	f
7332	293	51	BASICO	318	t	f
7333	293	52	AVANCADO	321	t	f
7334	293	28	BASICO	318	t	f
7335	293	29	AVANCADO	321	t	f
7336	293	30	BASICO	318	t	f
7337	293	31	BASICO	318	t	f
7338	293	32	BASICO	318	t	f
7339	293	33	AVANCADO	321	t	f
7340	293	34	INTERMEDIARIO	320	t	f
7341	293	35	INTERMEDIARIO	320	t	f
7342	293	36	INTERMEDIARIO	320	t	f
7343	293	37	BASICO	318	t	f
7344	293	38	BASICO	318	t	f
7345	293	39	BASICO	318	t	f
7346	293	40	AVANCADO	321	t	f
7347	293	41	INTERMEDIARIO	320	t	f
7348	293	42	INTERMEDIARIO	320	t	f
7349	293	43	INTERMEDIARIO	320	t	f
7350	293	44	INTERMEDIARIO	320	t	f
7351	293	45	BASICO	318	t	f
7352	293	46	BASICO	318	t	f
7353	293	13	BASICO	318	t	f
7354	293	14	INTERMEDIARIO	320	t	f
7355	293	15	INTERMEDIARIO	320	t	f
7356	293	16	AVANCADO	321	t	f
7357	293	17	BASICO	318	t	f
7358	293	18	BASICO	318	t	f
7359	293	19	INTERMEDIARIO	320	t	f
7360	293	20	BASICO	318	t	f
7361	293	21	INTERMEDIARIO	320	t	f
7362	293	22	BASICO	318	t	f
7363	293	23	INTERMEDIARIO	320	t	f
7364	293	24	BASICO	318	t	f
7365	293	25	BASICO	318	t	f
7366	293	26	AVANCADO	321	t	f
7367	293	27	BASICO	318	t	f
7368	293	53	AVANCADO	321	t	f
7369	293	54	AVANCADO	321	t	f
7370	293	55	INTERMEDIARIO	320	t	f
7371	293	56	AVANCADO	321	t	f
7372	293	57	BASICO	318	t	f
7373	293	58	INTERMEDIARIO	320	t	f
7374	293	59	INTERMEDIARIO	320	t	f
7375	293	60	INTERMEDIARIO	320	t	f
7376	293	61	INTERMEDIARIO	320	t	f
7377	293	62	BASICO	318	t	f
7378	293	83	BASICO	318	t	f
7379	293	84	AVANCADO	321	t	f
7380	293	85	BASICO	318	t	f
7381	293	86	BASICO	318	t	f
7382	293	87	BASICO	318	t	f
7383	293	88	BASICO	318	t	f
7384	293	89	BASICO	318	t	f
7385	293	90	BASICO	318	t	f
7386	293	91	BASICO	318	t	f
7387	293	92	BASICO	318	t	f
7388	293	93	BASICO	318	t	f
7389	293	94	BASICO	318	t	f
7390	293	95	BASICO	318	t	f
7391	293	96	BASICO	318	t	f
7392	293	97	BASICO	318	t	f
7393	293	130	BASICO	318	t	f
7394	293	113	INTERMEDIARIO	320	t	f
7395	293	115	AVANCADO	321	t	f
7396	293	116	INTERMEDIARIO	320	t	f
7397	293	117	AVANCADO	321	t	f
7398	293	118	AVANCADO	321	t	f
7399	293	119	INTERMEDIARIO	320	t	f
7400	293	120	INTERMEDIARIO	320	t	f
7401	293	121	BASICO	318	t	f
7402	293	122	BASICO	318	t	f
7403	293	123	BASICO	318	t	f
7404	293	124	BASICO	318	t	f
7405	293	125	BASICO	318	t	f
7406	293	126	BASICO	318	t	f
7407	293	127	BASICO	318	t	f
7408	293	129	BASICO	318	t	f
7409	293	1	AVANCADO	321	t	f
7410	293	2	BASICO	318	t	f
7411	293	3	INTERMEDIARIO	320	t	f
7412	293	4	BASICO	318	t	f
7413	293	5	INTERMEDIARIO	320	t	f
7414	293	6	BASICO	318	t	f
7415	293	7	BASICO	318	t	f
7416	293	8	BASICO	318	t	f
7417	293	9	BASICO	318	t	f
7418	293	10	BASICO	318	t	f
7419	293	11	INTERMEDIARIO	320	t	f
7420	293	12	AVANCADO	321	t	f
7421	293	63	INTERMEDIARIO	320	t	f
7422	293	64	INTERMEDIARIO	320	t	f
7423	293	65	AVANCADO	321	t	f
7424	293	66	AVANCADO	321	t	f
7425	293	67	INTERMEDIARIO	320	t	f
7426	293	68	INTERMEDIARIO	320	t	f
7427	293	69	BASICO	318	t	f
7428	293	70	BASICO	318	t	f
7429	293	71	BASICO	318	t	f
7430	293	72	INTERMEDIARIO	320	t	f
7431	293	73	BASICO	318	t	f
7432	293	74	BASICO	318	t	f
7433	293	75	BASICO	318	t	f
7434	293	76	BASICO	318	t	f
7435	293	77	BASICO	318	t	f
7436	293	78	BASICO	318	t	f
7437	293	79	BASICO	318	t	f
7438	293	81	BASICO	318	t	f
7439	293	82	BASICO	318	t	f
7440	293	108	BASICO	318	t	f
7441	293	109	AVANCADO	321	t	f
7442	293	110	BASICO	318	t	f
7443	293	111	INTERMEDIARIO	320	t	f
7444	293	112	BASICO	318	t	f
7445	71	98	BASICO	318	t	f
7446	71	99	BASICO	318	t	f
7447	71	100	BASICO	318	t	f
7448	71	101	BASICO	318	t	f
7449	71	102	BASICO	318	t	f
7450	71	103	BASICO	318	t	f
7451	71	104	BASICO	318	t	f
7452	71	105	BASICO	318	t	f
7453	71	106	INTERMEDIARIO	320	t	f
7454	71	107	INTERMEDIARIO	320	t	f
7455	71	47	BASICO	318	t	f
7456	71	48	BASICO	318	t	f
7457	71	49	BASICO	318	t	f
7458	71	50	AVANCADO	321	t	f
7459	71	51	BASICO	318	t	f
7460	71	52	INTERMEDIARIO	320	t	f
7461	71	28	BASICO	318	t	f
7462	71	29	AVANCADO	321	t	f
7463	71	30	AVANCADO	321	t	f
7464	71	31	BASICO	318	t	f
7465	71	32	BASICO	318	t	f
7466	71	33	INTERMEDIARIO	320	t	f
7467	71	34	INTERMEDIARIO	320	t	f
7468	71	35	INTERMEDIARIO	320	t	f
7469	71	36	AVANCADO	321	t	f
7470	71	37	AVANCADO	321	t	f
7471	71	38	BASICO	318	t	f
7472	71	39	BASICO	318	t	f
7473	71	40	AVANCADO	321	t	f
7474	71	41	AVANCADO	321	t	f
7475	71	42	BASICO	318	t	f
7476	71	43	AVANCADO	321	t	f
7477	71	44	AVANCADO	321	t	f
7478	71	45	BASICO	318	t	f
7479	71	46	BASICO	318	t	f
7480	71	13	BASICO	318	t	f
7481	71	14	BASICO	318	t	f
7482	71	15	BASICO	318	t	f
7483	71	16	BASICO	318	t	f
7484	71	17	BASICO	318	t	f
7485	71	18	AVANCADO	321	t	f
7486	71	19	INTERMEDIARIO	320	t	f
7487	71	20	AVANCADO	321	t	f
7488	71	21	BASICO	318	t	f
7489	71	22	BASICO	318	t	f
7490	71	23	BASICO	318	t	f
7491	71	24	BASICO	318	t	f
7492	71	25	BASICO	318	t	f
7493	71	26	BASICO	318	t	f
7494	71	27	BASICO	318	t	f
7495	71	53	INTERMEDIARIO	320	t	f
7496	71	54	INTERMEDIARIO	320	t	f
7497	71	55	AVANCADO	321	t	f
7498	71	56	AVANCADO	321	t	f
7499	71	57	BASICO	318	t	f
7500	71	58	AVANCADO	321	t	f
7501	71	59	INTERMEDIARIO	320	t	f
7502	71	60	INTERMEDIARIO	320	t	f
7503	71	61	INTERMEDIARIO	320	t	f
7504	71	62	AVANCADO	321	t	f
7505	71	83	BASICO	318	t	f
7506	71	84	BASICO	318	t	f
7507	71	85	BASICO	318	t	f
7508	71	86	BASICO	318	t	f
7509	71	87	BASICO	318	t	f
7510	71	88	BASICO	318	t	f
7511	71	89	BASICO	318	t	f
7512	71	90	BASICO	318	t	f
7513	71	91	BASICO	318	t	f
7514	71	92	BASICO	318	t	f
7515	71	93	BASICO	318	t	f
7516	71	94	BASICO	318	t	f
7517	71	95	BASICO	318	t	f
7518	71	96	BASICO	318	t	f
7519	71	97	BASICO	318	t	f
7520	71	130	BASICO	318	t	f
7521	71	113	INTERMEDIARIO	320	t	f
7522	71	114	INTERMEDIARIO	320	t	f
7523	71	115	AVANCADO	321	t	f
7524	71	116	AVANCADO	321	t	f
7525	71	117	AVANCADO	321	t	f
7526	71	118	AVANCADO	321	t	f
7527	71	119	AVANCADO	321	t	f
7528	71	120	AVANCADO	321	t	f
7529	71	121	BASICO	318	t	f
7530	71	122	BASICO	318	t	f
7531	71	123	BASICO	318	t	f
7532	71	124	BASICO	318	t	f
7533	71	125	BASICO	318	t	f
7534	71	126	BASICO	318	t	f
7535	71	127	BASICO	318	t	f
7536	71	129	INTERMEDIARIO	320	t	f
7537	71	1	BASICO	318	t	f
7538	71	2	BASICO	318	t	f
7539	71	3	BASICO	318	t	f
7540	71	4	BASICO	318	t	f
7541	71	5	BASICO	318	t	f
7542	71	6	BASICO	318	t	f
7543	71	7	BASICO	318	t	f
7544	71	8	BASICO	318	t	f
7545	71	9	BASICO	318	t	f
7546	71	10	BASICO	318	t	f
7547	71	11	BASICO	318	t	f
7548	71	12	BASICO	318	t	f
7549	71	63	INTERMEDIARIO	320	t	f
7550	71	64	BASICO	318	t	f
7551	71	65	INTERMEDIARIO	320	t	f
7552	71	66	INTERMEDIARIO	320	t	f
7553	71	67	BASICO	318	t	f
7554	71	68	BASICO	318	t	f
7555	71	69	BASICO	318	t	f
7556	71	70	BASICO	318	t	f
7557	71	71	INTERMEDIARIO	320	t	f
7558	71	72	INTERMEDIARIO	320	t	f
7559	71	73	BASICO	318	t	f
7560	71	74	BASICO	318	t	f
7561	71	75	BASICO	318	t	f
7562	71	76	INTERMEDIARIO	320	t	f
7563	71	77	BASICO	318	t	f
7564	71	78	BASICO	318	t	f
7565	71	79	BASICO	318	t	f
7566	71	81	BASICO	318	t	f
7567	71	82	BASICO	318	t	f
7568	71	108	AVANCADO	321	t	f
7569	71	109	AVANCADO	321	t	f
7570	71	110	BASICO	318	t	f
7571	71	111	INTERMEDIARIO	320	t	f
7572	71	112	INTERMEDIARIO	320	t	f
7573	248	99	BASICO	318	t	f
7574	248	100	BASICO	318	t	f
7575	248	101	BASICO	318	t	f
7576	248	103	INTERMEDIARIO	320	t	f
7577	248	104	INTERMEDIARIO	320	t	f
7578	248	105	INTERMEDIARIO	320	t	f
7579	248	107	BASICO	318	t	f
7580	248	47	BASICO	318	t	f
7581	248	48	BASICO	318	t	f
7582	248	49	INTERMEDIARIO	320	t	f
7583	248	51	INTERMEDIARIO	320	t	f
7584	248	52	AVANCADO	321	t	f
7585	248	28	BASICO	318	t	f
7586	248	29	AVANCADO	321	t	f
7587	248	30	AVANCADO	321	t	f
7588	248	31	BASICO	318	t	f
7589	248	32	BASICO	318	t	f
7590	248	35	INTERMEDIARIO	320	t	f
7591	248	37	INTERMEDIARIO	320	t	f
7592	248	39	BASICO	318	t	f
7593	248	40	INTERMEDIARIO	320	t	f
7594	248	41	INTERMEDIARIO	320	t	f
7595	248	42	BASICO	318	t	f
7596	248	43	INTERMEDIARIO	320	t	f
7597	248	44	INTERMEDIARIO	320	t	f
7598	248	45	BASICO	318	t	f
7599	248	46	BASICO	318	t	f
7600	248	13	BASICO	318	t	f
7601	248	14	BASICO	318	t	f
7602	248	15	INTERMEDIARIO	320	t	f
7603	248	17	BASICO	318	t	f
7604	248	21	BASICO	318	t	f
7605	248	22	BASICO	318	t	f
7606	248	23	BASICO	318	t	f
7607	248	24	BASICO	318	t	f
7608	248	25	BASICO	318	t	f
7609	248	27	BASICO	318	t	f
7610	248	54	BASICO	318	t	f
7611	248	55	AVANCADO	321	t	f
7612	248	56	AVANCADO	321	t	f
7613	248	57	BASICO	318	t	f
7614	248	58	AVANCADO	321	t	f
7615	248	84	BASICO	318	t	f
7616	248	85	BASICO	318	t	f
7617	248	86	BASICO	318	t	f
7618	248	87	BASICO	318	t	f
7619	248	88	BASICO	318	t	f
7620	248	89	BASICO	318	t	f
7621	248	90	BASICO	318	t	f
7622	248	91	BASICO	318	t	f
7623	248	92	BASICO	318	t	f
7624	248	93	BASICO	318	t	f
7625	248	94	BASICO	318	t	f
7626	248	95	BASICO	318	t	f
7627	248	96	BASICO	318	t	f
7628	248	97	BASICO	318	t	f
7629	248	130	BASICO	318	t	f
7630	248	113	AVANCADO	321	t	f
7631	248	114	AVANCADO	321	t	f
7632	248	115	AVANCADO	321	t	f
7633	248	116	AVANCADO	321	t	f
7634	248	117	AVANCADO	321	t	f
7635	248	118	AVANCADO	321	t	f
7636	248	121	BASICO	318	t	f
7637	248	122	BASICO	318	t	f
7638	248	123	INTERMEDIARIO	320	t	f
7639	248	124	INTERMEDIARIO	320	t	f
7640	248	125	BASICO	318	t	f
7641	248	126	AVANCADO	321	t	f
7642	248	127	BASICO	318	t	f
7643	248	129	INTERMEDIARIO	320	t	f
7644	248	1	INTERMEDIARIO	320	t	f
7645	248	2	BASICO	318	t	f
7646	248	3	INTERMEDIARIO	320	t	f
7647	248	4	BASICO	318	t	f
7648	248	5	BASICO	318	t	f
7649	248	6	BASICO	318	t	f
7650	248	7	BASICO	318	t	f
7651	248	8	INTERMEDIARIO	320	t	f
7652	248	9	INTERMEDIARIO	320	t	f
7653	248	10	INTERMEDIARIO	320	t	f
7654	248	11	BASICO	318	t	f
7655	248	12	INTERMEDIARIO	320	t	f
7656	248	63	BASICO	318	t	f
7657	248	64	INTERMEDIARIO	320	t	f
7658	248	66	INTERMEDIARIO	320	t	f
7659	248	67	INTERMEDIARIO	320	t	f
7660	248	68	BASICO	318	t	f
7661	248	69	BASICO	318	t	f
7662	248	70	BASICO	318	t	f
7663	248	71	INTERMEDIARIO	320	t	f
7664	248	72	BASICO	318	t	f
7665	248	73	BASICO	318	t	f
7666	248	74	BASICO	318	t	f
7667	248	75	INTERMEDIARIO	320	t	f
7668	248	76	INTERMEDIARIO	320	t	f
7669	248	77	BASICO	318	t	f
7670	248	78	BASICO	318	t	f
7671	248	79	BASICO	318	t	f
7672	248	81	BASICO	318	t	f
7673	248	82	BASICO	318	t	f
7674	248	108	AVANCADO	321	t	f
7675	248	109	AVANCADO	321	t	f
7676	248	110	BASICO	318	t	f
7677	248	111	INTERMEDIARIO	320	t	f
7678	248	112	BASICO	318	t	f
7679	95	98	BASICO	318	t	f
7680	95	106	INTERMEDIARIO	320	t	f
7681	95	50	BASICO	318	t	f
7682	95	52	BASICO	318	t	f
7683	95	30	INTERMEDIARIO	320	t	f
7684	95	35	INTERMEDIARIO	320	t	f
7685	95	36	INTERMEDIARIO	320	t	f
7686	95	38	BASICO	318	t	f
7687	95	40	INTERMEDIARIO	320	t	f
7688	95	41	INTERMEDIARIO	320	t	f
7689	95	43	INTERMEDIARIO	320	t	f
7690	95	44	INTERMEDIARIO	320	t	f
7691	95	13	BASICO	318	t	f
7692	95	14	INTERMEDIARIO	320	t	f
7693	95	15	BASICO	318	t	f
7694	95	18	BASICO	318	t	f
7695	95	21	INTERMEDIARIO	320	t	f
7696	95	55	INTERMEDIARIO	320	t	f
7697	95	56	INTERMEDIARIO	320	t	f
7698	95	58	INTERMEDIARIO	320	t	f
7699	95	59	BASICO	318	t	f
7700	95	94	BASICO	318	t	f
7701	95	115	BASICO	318	t	f
7702	95	117	INTERMEDIARIO	320	t	f
7703	95	10	BASICO	318	t	f
7704	95	63	BASICO	318	t	f
7705	95	64	BASICO	318	t	f
7706	95	72	BASICO	318	t	f
7707	95	108	BASICO	318	t	f
7708	114	99	BASICO	318	t	f
7709	114	101	BASICO	318	t	f
7710	114	103	INTERMEDIARIO	320	t	f
7711	114	104	BASICO	318	t	f
7712	114	105	BASICO	318	t	f
7713	114	107	INTERMEDIARIO	320	t	f
7714	114	47	BASICO	318	t	f
7715	114	48	BASICO	318	t	f
7716	114	49	BASICO	318	t	f
7717	114	50	AVANCADO	321	t	f
7718	114	51	BASICO	318	t	f
7719	114	52	INTERMEDIARIO	320	t	f
7720	114	28	BASICO	318	t	f
7721	114	29	INTERMEDIARIO	320	t	f
7722	114	30	AVANCADO	321	t	f
7723	114	31	BASICO	318	t	f
7724	114	32	BASICO	318	t	f
7725	114	37	INTERMEDIARIO	320	t	f
7726	114	39	INTERMEDIARIO	320	t	f
7727	114	40	INTERMEDIARIO	320	t	f
7728	114	41	AVANCADO	321	t	f
7729	114	42	BASICO	318	t	f
7730	114	43	INTERMEDIARIO	320	t	f
7731	114	44	AVANCADO	321	t	f
7732	114	45	BASICO	318	t	f
7733	114	46	BASICO	318	t	f
7734	114	13	BASICO	318	t	f
7735	114	14	BASICO	318	t	f
7736	114	15	AVANCADO	321	t	f
7737	114	16	INTERMEDIARIO	320	t	f
7738	114	17	BASICO	318	t	f
7739	114	18	AVANCADO	321	t	f
7740	114	19	INTERMEDIARIO	320	t	f
7741	114	21	AVANCADO	321	t	f
7742	114	22	BASICO	318	t	f
7743	114	23	BASICO	318	t	f
7744	114	24	BASICO	318	t	f
7745	114	25	BASICO	318	t	f
7746	114	26	AVANCADO	321	t	f
7747	114	27	BASICO	318	t	f
7748	114	54	AVANCADO	321	t	f
7749	114	55	AVANCADO	321	t	f
7750	114	56	AVANCADO	321	t	f
7751	114	57	BASICO	318	t	f
7752	114	84	BASICO	318	t	f
7753	114	85	INTERMEDIARIO	320	t	f
7754	114	86	BASICO	318	t	f
7755	114	87	BASICO	318	t	f
7756	114	88	BASICO	318	t	f
7757	114	89	BASICO	318	t	f
7758	114	90	BASICO	318	t	f
7759	114	91	INTERMEDIARIO	320	t	f
7760	114	93	BASICO	318	t	f
7761	114	94	BASICO	318	t	f
7762	114	95	BASICO	318	t	f
7763	114	96	BASICO	318	t	f
7764	114	97	BASICO	318	t	f
7765	114	130	BASICO	318	t	f
7766	114	113	AVANCADO	321	t	f
7767	114	114	INTERMEDIARIO	320	t	f
7768	114	115	AVANCADO	321	t	f
7769	114	116	INTERMEDIARIO	320	t	f
7770	114	117	AVANCADO	321	t	f
7771	114	118	INTERMEDIARIO	320	t	f
7772	114	121	BASICO	318	t	f
7773	114	122	INTERMEDIARIO	320	t	f
7774	114	123	INTERMEDIARIO	320	t	f
7775	114	124	BASICO	318	t	f
7776	114	125	BASICO	318	t	f
7777	114	126	INTERMEDIARIO	320	t	f
7778	114	127	BASICO	318	t	f
7779	114	129	AVANCADO	321	t	f
7780	114	1	BASICO	318	t	f
7781	114	2	INTERMEDIARIO	320	t	f
7782	114	3	BASICO	318	t	f
7783	114	4	INTERMEDIARIO	320	t	f
7784	114	5	INTERMEDIARIO	320	t	f
7785	114	6	INTERMEDIARIO	320	t	f
7786	114	7	INTERMEDIARIO	320	t	f
7787	114	8	AVANCADO	321	t	f
7788	114	9	AVANCADO	321	t	f
7789	114	10	BASICO	318	t	f
7790	114	11	INTERMEDIARIO	320	t	f
7791	114	12	AVANCADO	321	t	f
7792	114	63	INTERMEDIARIO	320	t	f
7793	114	64	INTERMEDIARIO	320	t	f
7794	114	66	AVANCADO	321	t	f
7795	114	67	INTERMEDIARIO	320	t	f
7796	114	68	AVANCADO	321	t	f
7797	114	69	BASICO	318	t	f
7798	114	70	INTERMEDIARIO	320	t	f
7799	114	71	INTERMEDIARIO	320	t	f
7800	114	72	INTERMEDIARIO	320	t	f
7801	114	73	BASICO	318	t	f
7802	114	74	BASICO	318	t	f
7803	114	75	INTERMEDIARIO	320	t	f
7804	114	76	INTERMEDIARIO	320	t	f
7805	114	77	INTERMEDIARIO	320	t	f
7806	114	78	BASICO	318	t	f
7807	114	79	BASICO	318	t	f
7808	114	81	INTERMEDIARIO	320	t	f
7809	114	82	BASICO	318	t	f
7810	114	108	AVANCADO	321	t	f
7811	114	109	AVANCADO	321	t	f
7812	114	110	INTERMEDIARIO	320	t	f
7813	114	111	AVANCADO	321	t	f
7814	114	112	BASICO	318	t	f
7815	271	98	BASICO	318	t	f
7816	271	100	AVANCADO	321	t	f
7817	271	104	INTERMEDIARIO	320	t	f
7818	271	105	INTERMEDIARIO	320	t	f
7819	271	107	AVANCADO	321	t	f
7820	271	48	BASICO	318	t	f
7821	271	49	INTERMEDIARIO	320	t	f
7822	271	52	INTERMEDIARIO	320	t	f
7823	271	28	BASICO	318	t	f
7824	271	29	INTERMEDIARIO	320	t	f
7825	271	37	BASICO	318	t	f
7826	271	40	INTERMEDIARIO	320	t	f
7827	271	42	BASICO	318	t	f
7828	271	43	BASICO	318	t	f
7829	271	44	INTERMEDIARIO	320	t	f
7830	271	45	BASICO	318	t	f
7831	271	13	INTERMEDIARIO	320	t	f
7832	271	14	BASICO	318	t	f
7833	271	15	BASICO	318	t	f
7834	271	19	INTERMEDIARIO	320	t	f
7835	271	55	INTERMEDIARIO	320	t	f
7836	271	56	AVANCADO	321	t	f
7837	271	59	BASICO	318	t	f
7838	271	60	BASICO	318	t	f
7839	271	61	INTERMEDIARIO	320	t	f
7840	271	84	BASICO	318	t	f
7841	271	113	BASICO	318	t	f
7842	271	115	AVANCADO	321	t	f
7843	271	116	AVANCADO	321	t	f
7844	271	117	BASICO	318	t	f
7845	271	118	BASICO	318	t	f
7846	271	119	AVANCADO	321	t	f
7847	271	120	INTERMEDIARIO	320	t	f
7848	271	122	BASICO	318	t	f
7849	271	124	INTERMEDIARIO	320	t	f
7850	271	126	INTERMEDIARIO	320	t	f
7851	271	129	INTERMEDIARIO	320	t	f
7852	271	1	INTERMEDIARIO	320	t	f
7853	271	4	INTERMEDIARIO	320	t	f
7854	271	6	INTERMEDIARIO	320	t	f
7855	271	8	BASICO	318	t	f
7856	271	63	BASICO	318	t	f
7857	271	66	INTERMEDIARIO	320	t	f
7858	271	72	BASICO	318	t	f
7859	271	75	BASICO	318	t	f
7860	271	76	INTERMEDIARIO	320	t	f
7861	271	82	BASICO	318	t	f
7862	271	108	INTERMEDIARIO	320	t	f
7863	271	109	BASICO	318	t	f
7864	271	111	BASICO	318	t	f
7865	145	102	BASICO	318	t	f
7866	145	104	BASICO	318	t	f
7867	145	107	BASICO	318	t	f
7868	145	51	BASICO	318	t	f
7869	145	33	BASICO	318	t	f
7870	145	34	BASICO	318	t	f
7871	145	36	BASICO	318	t	f
7872	145	17	BASICO	318	t	f
7873	145	21	INTERMEDIARIO	320	t	f
7874	145	55	BASICO	318	t	f
7875	145	56	BASICO	318	t	f
7876	145	58	BASICO	318	t	f
7877	145	87	BASICO	318	t	f
7878	145	88	BASICO	318	t	f
7879	145	92	BASICO	318	t	f
7880	145	113	INTERMEDIARIO	320	t	f
7881	145	114	INTERMEDIARIO	320	t	f
7882	145	115	INTERMEDIARIO	320	t	f
7883	145	116	BASICO	318	t	f
7884	145	117	INTERMEDIARIO	320	t	f
7885	145	118	BASICO	318	t	f
7886	145	119	INTERMEDIARIO	320	t	f
7887	145	121	INTERMEDIARIO	320	t	f
7888	145	122	BASICO	318	t	f
7889	145	123	INTERMEDIARIO	320	t	f
7890	145	124	AVANCADO	321	t	f
7891	145	125	BASICO	318	t	f
7892	145	126	BASICO	318	t	f
7893	145	129	AVANCADO	321	t	f
7894	145	1	BASICO	318	t	f
7895	145	4	INTERMEDIARIO	320	t	f
7896	145	5	INTERMEDIARIO	320	t	f
7897	145	7	BASICO	318	t	f
7898	145	8	INTERMEDIARIO	320	t	f
7899	145	9	BASICO	318	t	f
7900	145	11	BASICO	318	t	f
7901	145	12	BASICO	318	t	f
7902	145	63	INTERMEDIARIO	320	t	f
7903	145	64	INTERMEDIARIO	320	t	f
7904	145	65	AVANCADO	321	t	f
7905	145	66	AVANCADO	321	t	f
7906	145	67	AVANCADO	321	t	f
7907	145	68	INTERMEDIARIO	320	t	f
7908	145	69	BASICO	318	t	f
7909	145	70	INTERMEDIARIO	320	t	f
7910	145	71	INTERMEDIARIO	320	t	f
7911	145	72	AVANCADO	321	t	f
7912	145	73	AVANCADO	321	t	f
7913	145	75	AVANCADO	321	t	f
7914	145	76	INTERMEDIARIO	320	t	f
7915	145	77	INTERMEDIARIO	320	t	f
7916	145	79	INTERMEDIARIO	320	t	f
7917	145	82	INTERMEDIARIO	320	t	f
7918	145	108	INTERMEDIARIO	320	t	f
7919	145	109	INTERMEDIARIO	320	t	f
7920	145	111	INTERMEDIARIO	320	t	f
7921	53	98	BASICO	318	t	f
7922	53	99	BASICO	318	t	f
7923	53	100	BASICO	318	t	f
7924	53	102	BASICO	318	t	f
7925	53	103	BASICO	318	t	f
7926	53	104	INTERMEDIARIO	320	t	f
7927	53	105	AVANCADO	321	t	f
7928	53	106	AVANCADO	321	t	f
7929	53	107	INTERMEDIARIO	320	t	f
7930	53	47	AVANCADO	321	t	f
7931	53	48	BASICO	318	t	f
7932	53	49	INTERMEDIARIO	320	t	f
7933	53	50	AVANCADO	321	t	f
7934	53	51	AVANCADO	321	t	f
7935	53	52	BASICO	318	t	f
7936	53	28	BASICO	318	t	f
7937	53	29	AVANCADO	321	t	f
7938	53	30	BASICO	318	t	f
7939	53	31	BASICO	318	t	f
7940	53	32	BASICO	318	t	f
7941	53	33	AVANCADO	321	t	f
7942	53	34	AVANCADO	321	t	f
7943	53	35	BASICO	318	t	f
7944	53	37	AVANCADO	321	t	f
7945	53	38	BASICO	318	t	f
7946	53	39	BASICO	318	t	f
7947	53	40	AVANCADO	321	t	f
7948	53	42	AVANCADO	321	t	f
7949	53	43	BASICO	318	t	f
7950	53	44	AVANCADO	321	t	f
7951	53	45	BASICO	318	t	f
7952	53	46	BASICO	318	t	f
7953	53	13	BASICO	318	t	f
7954	53	14	INTERMEDIARIO	320	t	f
7955	53	16	INTERMEDIARIO	320	t	f
7956	53	17	BASICO	318	t	f
7957	53	22	BASICO	318	t	f
7958	53	23	BASICO	318	t	f
7959	53	24	BASICO	318	t	f
7960	53	25	BASICO	318	t	f
7961	53	27	BASICO	318	t	f
7962	53	53	INTERMEDIARIO	320	t	f
7963	53	54	INTERMEDIARIO	320	t	f
7964	53	57	BASICO	318	t	f
7965	53	60	AVANCADO	321	t	f
7966	53	62	INTERMEDIARIO	320	t	f
7967	53	83	BASICO	318	t	f
7968	53	84	BASICO	318	t	f
7969	53	85	BASICO	318	t	f
7970	53	87	BASICO	318	t	f
7971	53	88	BASICO	318	t	f
7972	53	89	BASICO	318	t	f
7973	53	90	BASICO	318	t	f
7974	53	91	BASICO	318	t	f
7975	53	92	BASICO	318	t	f
7976	53	93	BASICO	318	t	f
7977	53	94	BASICO	318	t	f
7978	53	95	BASICO	318	t	f
7979	53	96	BASICO	318	t	f
7980	53	97	BASICO	318	t	f
7981	53	130	BASICO	318	t	f
7982	53	113	AVANCADO	321	t	f
7983	53	114	AVANCADO	321	t	f
7984	53	115	AVANCADO	321	t	f
7985	53	116	AVANCADO	321	t	f
7986	53	117	AVANCADO	321	t	f
7987	53	118	AVANCADO	321	t	f
7988	53	119	AVANCADO	321	t	f
7989	53	120	AVANCADO	321	t	f
7990	53	121	BASICO	318	t	f
7991	53	122	BASICO	318	t	f
7992	53	123	BASICO	318	t	f
7993	53	124	INTERMEDIARIO	320	t	f
7994	53	125	BASICO	318	t	f
7995	53	126	BASICO	318	t	f
7996	53	127	BASICO	318	t	f
7997	53	129	AVANCADO	321	t	f
7998	53	1	AVANCADO	321	t	f
7999	53	2	BASICO	318	t	f
8000	53	3	BASICO	318	t	f
8001	53	4	AVANCADO	321	t	f
8002	53	5	INTERMEDIARIO	320	t	f
8003	53	6	BASICO	318	t	f
8004	53	7	BASICO	318	t	f
8005	53	8	AVANCADO	321	t	f
8006	53	9	AVANCADO	321	t	f
8007	53	10	BASICO	318	t	f
8008	53	11	BASICO	318	t	f
8009	53	12	AVANCADO	321	t	f
8010	53	63	INTERMEDIARIO	320	t	f
8011	53	64	BASICO	318	t	f
8012	53	67	INTERMEDIARIO	320	t	f
8013	53	68	BASICO	318	t	f
8014	53	69	AVANCADO	321	t	f
8015	53	70	BASICO	318	t	f
8016	53	71	BASICO	318	t	f
8017	53	72	AVANCADO	321	t	f
8018	53	73	INTERMEDIARIO	320	t	f
8019	53	74	AVANCADO	321	t	f
8020	53	75	INTERMEDIARIO	320	t	f
8021	53	76	BASICO	318	t	f
8022	53	77	BASICO	318	t	f
8023	53	78	BASICO	318	t	f
8024	53	79	BASICO	318	t	f
8025	53	81	BASICO	318	t	f
8026	53	82	AVANCADO	321	t	f
8027	53	108	AVANCADO	321	t	f
8028	53	109	AVANCADO	321	t	f
8029	53	110	AVANCADO	321	t	f
8030	53	111	AVANCADO	321	t	f
8031	53	112	INTERMEDIARIO	320	t	f
8032	127	98	AVANCADO	321	t	f
8033	127	99	AVANCADO	321	t	f
8034	127	100	AVANCADO	321	t	f
8035	127	101	INTERMEDIARIO	320	t	f
8036	127	102	AVANCADO	321	t	f
8037	127	103	AVANCADO	321	t	f
8038	127	104	INTERMEDIARIO	320	t	f
8039	127	105	AVANCADO	321	t	f
8040	127	106	AVANCADO	321	t	f
8041	127	107	AVANCADO	321	t	f
8042	127	47	INTERMEDIARIO	320	t	f
8043	127	48	AVANCADO	321	t	f
8044	127	49	INTERMEDIARIO	320	t	f
8045	127	50	AVANCADO	321	t	f
8046	127	51	INTERMEDIARIO	320	t	f
8047	127	52	INTERMEDIARIO	320	t	f
8048	127	28	BASICO	318	t	f
8049	127	29	BASICO	318	t	f
8050	127	30	BASICO	318	t	f
8051	127	31	BASICO	318	t	f
8052	127	32	BASICO	318	t	f
8053	127	33	INTERMEDIARIO	320	t	f
8054	127	34	INTERMEDIARIO	320	t	f
8055	127	35	INTERMEDIARIO	320	t	f
8056	127	36	INTERMEDIARIO	320	t	f
8057	127	37	INTERMEDIARIO	320	t	f
8058	127	38	INTERMEDIARIO	320	t	f
8059	127	39	INTERMEDIARIO	320	t	f
8060	127	40	INTERMEDIARIO	320	t	f
8061	127	41	INTERMEDIARIO	320	t	f
8062	127	42	INTERMEDIARIO	320	t	f
8063	127	43	INTERMEDIARIO	320	t	f
8064	127	44	INTERMEDIARIO	320	t	f
8065	127	45	BASICO	318	t	f
8066	127	46	BASICO	318	t	f
8067	127	13	BASICO	318	t	f
8068	127	14	AVANCADO	321	t	f
8069	127	15	BASICO	318	t	f
8070	127	16	INTERMEDIARIO	320	t	f
8071	127	17	AVANCADO	321	t	f
8072	127	18	AVANCADO	321	t	f
8073	127	19	AVANCADO	321	t	f
8074	127	20	AVANCADO	321	t	f
8075	127	21	AVANCADO	321	t	f
8076	127	22	BASICO	318	t	f
8077	127	23	BASICO	318	t	f
8078	127	24	BASICO	318	t	f
8079	127	25	BASICO	318	t	f
8080	127	26	BASICO	318	t	f
8081	127	27	BASICO	318	t	f
8082	127	53	BASICO	318	t	f
8083	127	54	BASICO	318	t	f
8084	127	55	AVANCADO	321	t	f
8085	127	56	AVANCADO	321	t	f
8086	127	57	BASICO	318	t	f
8087	127	58	INTERMEDIARIO	320	t	f
8088	127	59	BASICO	318	t	f
8089	127	60	BASICO	318	t	f
8090	127	61	BASICO	318	t	f
8091	127	62	BASICO	318	t	f
8092	127	83	BASICO	318	t	f
8093	127	84	BASICO	318	t	f
8094	127	85	BASICO	318	t	f
8095	127	86	BASICO	318	t	f
8096	127	87	BASICO	318	t	f
8097	127	88	BASICO	318	t	f
8098	127	89	BASICO	318	t	f
8099	127	90	BASICO	318	t	f
8100	127	91	BASICO	318	t	f
8101	127	92	BASICO	318	t	f
8102	127	93	BASICO	318	t	f
8103	127	94	INTERMEDIARIO	320	t	f
8104	127	95	BASICO	318	t	f
8105	127	96	BASICO	318	t	f
8106	127	97	BASICO	318	t	f
8107	127	130	BASICO	318	t	f
8108	127	113	INTERMEDIARIO	320	t	f
8109	127	114	INTERMEDIARIO	320	t	f
8110	127	115	AVANCADO	321	t	f
8111	127	116	BASICO	318	t	f
8112	127	117	AVANCADO	321	t	f
8113	127	118	INTERMEDIARIO	320	t	f
8114	127	119	AVANCADO	321	t	f
8115	127	120	INTERMEDIARIO	320	t	f
8116	127	121	BASICO	318	t	f
8117	127	122	BASICO	318	t	f
8118	127	123	BASICO	318	t	f
8119	127	124	BASICO	318	t	f
8120	127	125	BASICO	318	t	f
8121	127	126	BASICO	318	t	f
8122	127	127	BASICO	318	t	f
8123	127	129	BASICO	318	t	f
8124	127	1	INTERMEDIARIO	320	t	f
8125	127	2	AVANCADO	321	t	f
8126	127	3	INTERMEDIARIO	320	t	f
8127	127	4	BASICO	318	t	f
8128	127	5	BASICO	318	t	f
8129	127	6	BASICO	318	t	f
8130	127	7	BASICO	318	t	f
8131	127	8	BASICO	318	t	f
8132	127	9	BASICO	318	t	f
8133	127	10	INTERMEDIARIO	320	t	f
8134	127	11	BASICO	318	t	f
8135	127	12	AVANCADO	321	t	f
8136	127	63	INTERMEDIARIO	320	t	f
8137	127	64	AVANCADO	321	t	f
8138	127	65	BASICO	318	t	f
8139	127	66	BASICO	318	t	f
8140	127	67	BASICO	318	t	f
8141	127	68	BASICO	318	t	f
8142	127	69	BASICO	318	t	f
8143	127	70	BASICO	318	t	f
8144	127	71	BASICO	318	t	f
8145	127	72	BASICO	318	t	f
8146	127	73	BASICO	318	t	f
8147	127	74	INTERMEDIARIO	320	t	f
8148	127	75	BASICO	318	t	f
8149	127	76	BASICO	318	t	f
8150	127	77	BASICO	318	t	f
8151	127	78	BASICO	318	t	f
8152	127	79	BASICO	318	t	f
8153	127	81	BASICO	318	t	f
8154	127	82	INTERMEDIARIO	320	t	f
8155	127	108	INTERMEDIARIO	320	t	f
8156	127	109	BASICO	318	t	f
8157	127	110	AVANCADO	321	t	f
8158	127	111	INTERMEDIARIO	320	t	f
8159	127	112	BASICO	318	t	f
8160	191	105	BASICO	318	t	f
8161	191	106	INTERMEDIARIO	320	t	f
8162	191	107	INTERMEDIARIO	320	t	f
8163	191	49	BASICO	318	t	f
8164	191	50	INTERMEDIARIO	320	t	f
8165	191	52	AVANCADO	321	t	f
8166	191	29	AVANCADO	321	t	f
8167	191	30	INTERMEDIARIO	320	t	f
8168	191	37	AVANCADO	321	t	f
8169	191	42	INTERMEDIARIO	320	t	f
8170	191	14	INTERMEDIARIO	320	t	f
8171	191	15	AVANCADO	321	t	f
8172	191	53	INTERMEDIARIO	320	t	f
8173	191	54	INTERMEDIARIO	320	t	f
8174	191	55	AVANCADO	321	t	f
8175	191	56	AVANCADO	321	t	f
8176	191	58	AVANCADO	321	t	f
8177	191	61	AVANCADO	321	t	f
8178	191	86	INTERMEDIARIO	320	t	f
8179	191	94	INTERMEDIARIO	320	t	f
8180	191	113	INTERMEDIARIO	320	t	f
8181	191	114	INTERMEDIARIO	320	t	f
8182	191	115	AVANCADO	321	t	f
8183	191	116	AVANCADO	321	t	f
8184	191	117	AVANCADO	321	t	f
8185	191	119	AVANCADO	321	t	f
8186	191	120	AVANCADO	321	t	f
8187	191	124	INTERMEDIARIO	320	t	f
8188	191	129	AVANCADO	321	t	f
8189	191	1	INTERMEDIARIO	320	t	f
8190	191	4	INTERMEDIARIO	320	t	f
8191	191	8	BASICO	318	t	f
8192	191	9	INTERMEDIARIO	320	t	f
8193	191	12	INTERMEDIARIO	320	t	f
8194	191	63	INTERMEDIARIO	320	t	f
8195	191	68	INTERMEDIARIO	320	t	f
8196	191	72	AVANCADO	321	t	f
8197	191	74	AVANCADO	321	t	f
8198	191	75	AVANCADO	321	t	f
8199	191	76	BASICO	318	t	f
8200	191	78	BASICO	318	t	f
8201	191	81	INTERMEDIARIO	320	t	f
8202	191	82	BASICO	318	t	f
8203	191	108	AVANCADO	321	t	f
8204	191	109	AVANCADO	321	t	f
8205	191	110	AVANCADO	321	t	f
8206	191	111	AVANCADO	321	t	f
8207	310	98	BASICO	318	t	f
8208	310	99	BASICO	318	t	f
8209	310	100	BASICO	318	t	f
8210	310	101	BASICO	318	t	f
8211	310	102	INTERMEDIARIO	320	t	f
8212	310	103	BASICO	318	t	f
8213	310	104	BASICO	318	t	f
8214	310	105	BASICO	318	t	f
8215	310	106	BASICO	318	t	f
8216	310	107	BASICO	318	t	f
8217	310	47	BASICO	318	t	f
8218	310	48	BASICO	318	t	f
8219	310	49	INTERMEDIARIO	320	t	f
8220	310	50	INTERMEDIARIO	320	t	f
8221	310	51	BASICO	318	t	f
8222	310	52	INTERMEDIARIO	320	t	f
8223	310	28	BASICO	318	t	f
8224	310	29	INTERMEDIARIO	320	t	f
8225	310	30	AVANCADO	321	t	f
8226	310	31	BASICO	318	t	f
8227	310	32	BASICO	318	t	f
8228	310	33	INTERMEDIARIO	320	t	f
8229	310	34	INTERMEDIARIO	320	t	f
8230	310	35	INTERMEDIARIO	320	t	f
8231	310	36	INTERMEDIARIO	320	t	f
8232	310	37	AVANCADO	321	t	f
8233	310	38	INTERMEDIARIO	320	t	f
8234	310	39	BASICO	318	t	f
8235	310	40	BASICO	318	t	f
8236	310	41	AVANCADO	321	t	f
8237	310	42	BASICO	318	t	f
8238	310	43	INTERMEDIARIO	320	t	f
8239	310	44	BASICO	318	t	f
8240	310	45	BASICO	318	t	f
8241	310	46	BASICO	318	t	f
8242	310	13	BASICO	318	t	f
8243	310	14	BASICO	318	t	f
8244	310	15	BASICO	318	t	f
8245	310	16	INTERMEDIARIO	320	t	f
8246	310	17	BASICO	318	t	f
8247	310	18	INTERMEDIARIO	320	t	f
8248	310	19	INTERMEDIARIO	320	t	f
8249	310	20	INTERMEDIARIO	320	t	f
8250	310	21	INTERMEDIARIO	320	t	f
8251	310	22	BASICO	318	t	f
8252	310	23	BASICO	318	t	f
8253	310	24	BASICO	318	t	f
8254	310	25	BASICO	318	t	f
8255	310	26	BASICO	318	t	f
8256	310	27	BASICO	318	t	f
8257	310	53	BASICO	318	t	f
8258	310	54	BASICO	318	t	f
8259	310	55	INTERMEDIARIO	320	t	f
8260	310	56	INTERMEDIARIO	320	t	f
8261	310	57	BASICO	318	t	f
8262	310	58	AVANCADO	321	t	f
8263	310	59	AVANCADO	321	t	f
8264	310	60	AVANCADO	321	t	f
8265	310	61	AVANCADO	321	t	f
8266	310	62	BASICO	318	t	f
8267	310	83	BASICO	318	t	f
8268	310	84	BASICO	318	t	f
8269	310	85	BASICO	318	t	f
8270	310	86	BASICO	318	t	f
8271	310	87	BASICO	318	t	f
8272	310	88	BASICO	318	t	f
8273	310	89	BASICO	318	t	f
8274	310	90	BASICO	318	t	f
8275	310	91	BASICO	318	t	f
8276	310	92	BASICO	318	t	f
8277	310	93	BASICO	318	t	f
8278	310	94	BASICO	318	t	f
8279	310	95	BASICO	318	t	f
8280	310	96	BASICO	318	t	f
8281	310	97	BASICO	318	t	f
8282	310	130	BASICO	318	t	f
8283	310	113	BASICO	318	t	f
8284	310	114	BASICO	318	t	f
8285	310	115	INTERMEDIARIO	320	t	f
8286	310	116	BASICO	318	t	f
8287	310	117	INTERMEDIARIO	320	t	f
8288	310	118	BASICO	318	t	f
8289	310	119	BASICO	318	t	f
8290	310	120	BASICO	318	t	f
8291	310	121	BASICO	318	t	f
8292	310	122	BASICO	318	t	f
8293	310	123	BASICO	318	t	f
8294	310	124	BASICO	318	t	f
8295	310	125	BASICO	318	t	f
8296	310	126	BASICO	318	t	f
8297	310	127	BASICO	318	t	f
8298	310	129	INTERMEDIARIO	320	t	f
8299	310	1	BASICO	318	t	f
8300	310	2	BASICO	318	t	f
8301	310	3	BASICO	318	t	f
8302	310	4	BASICO	318	t	f
8303	310	5	BASICO	318	t	f
8304	310	6	BASICO	318	t	f
8305	310	7	BASICO	318	t	f
8306	310	8	BASICO	318	t	f
8307	310	9	BASICO	318	t	f
8308	310	10	BASICO	318	t	f
8309	310	11	BASICO	318	t	f
8310	310	12	BASICO	318	t	f
8311	310	63	BASICO	318	t	f
8312	310	64	BASICO	318	t	f
8313	310	65	INTERMEDIARIO	320	t	f
8314	310	66	INTERMEDIARIO	320	t	f
8315	310	67	BASICO	318	t	f
8316	310	68	BASICO	318	t	f
8317	310	69	BASICO	318	t	f
8318	310	70	BASICO	318	t	f
8319	310	71	BASICO	318	t	f
8320	310	72	BASICO	318	t	f
8321	310	73	BASICO	318	t	f
8322	310	74	BASICO	318	t	f
8323	310	75	BASICO	318	t	f
8324	310	76	BASICO	318	t	f
8325	310	77	BASICO	318	t	f
8326	310	78	BASICO	318	t	f
8327	310	79	BASICO	318	t	f
8328	310	81	BASICO	318	t	f
8329	310	82	BASICO	318	t	f
8330	310	108	BASICO	318	t	f
8331	310	109	BASICO	318	t	f
8332	310	110	BASICO	318	t	f
8333	310	111	BASICO	318	t	f
8334	310	112	BASICO	318	t	f
8335	154	98	INTERMEDIARIO	320	t	f
8336	154	99	INTERMEDIARIO	320	t	f
8337	154	100	INTERMEDIARIO	320	t	f
8338	154	101	INTERMEDIARIO	320	t	f
8339	154	102	INTERMEDIARIO	320	t	f
8340	154	103	AVANCADO	321	t	f
8341	154	104	INTERMEDIARIO	320	t	f
8342	154	105	INTERMEDIARIO	320	t	f
8343	154	106	BASICO	318	t	f
8344	154	107	BASICO	318	t	f
8345	154	47	BASICO	318	t	f
8346	154	49	BASICO	318	t	f
8347	154	50	INTERMEDIARIO	320	t	f
8348	154	51	BASICO	318	t	f
8349	154	52	INTERMEDIARIO	320	t	f
8350	154	28	INTERMEDIARIO	320	t	f
8351	154	29	INTERMEDIARIO	320	t	f
8352	154	30	INTERMEDIARIO	320	t	f
8353	154	31	INTERMEDIARIO	320	t	f
8354	154	32	BASICO	318	t	f
8355	154	33	BASICO	318	t	f
8356	154	36	INTERMEDIARIO	320	t	f
8357	154	37	INTERMEDIARIO	320	t	f
8358	154	38	INTERMEDIARIO	320	t	f
8359	154	39	BASICO	318	t	f
8360	154	41	BASICO	318	t	f
8361	154	44	BASICO	318	t	f
8362	154	45	BASICO	318	t	f
8363	154	46	BASICO	318	t	f
8364	154	13	BASICO	318	t	f
8365	154	14	AVANCADO	321	t	f
8366	154	15	BASICO	318	t	f
8367	154	16	INTERMEDIARIO	320	t	f
8368	154	17	INTERMEDIARIO	320	t	f
8369	154	18	BASICO	318	t	f
8370	154	19	INTERMEDIARIO	320	t	f
8371	154	22	INTERMEDIARIO	320	t	f
8372	154	23	BASICO	318	t	f
8373	154	24	BASICO	318	t	f
8374	154	25	BASICO	318	t	f
8375	154	26	INTERMEDIARIO	320	t	f
8376	154	27	BASICO	318	t	f
8377	154	53	BASICO	318	t	f
8378	154	54	BASICO	318	t	f
8379	154	55	BASICO	318	t	f
8380	154	56	INTERMEDIARIO	320	t	f
8381	154	57	BASICO	318	t	f
8382	154	58	INTERMEDIARIO	320	t	f
8383	154	59	BASICO	318	t	f
8384	154	60	BASICO	318	t	f
8385	154	61	INTERMEDIARIO	320	t	f
8386	154	62	BASICO	318	t	f
8387	154	83	BASICO	318	t	f
8388	154	88	BASICO	318	t	f
8389	154	94	BASICO	318	t	f
8390	154	96	BASICO	318	t	f
8391	154	115	INTERMEDIARIO	320	t	f
8392	154	116	INTERMEDIARIO	320	t	f
8393	154	117	INTERMEDIARIO	320	t	f
8394	154	118	INTERMEDIARIO	320	t	f
8395	154	119	INTERMEDIARIO	320	t	f
8396	154	120	INTERMEDIARIO	320	t	f
8397	154	121	BASICO	318	t	f
8398	154	7	INTERMEDIARIO	320	t	f
8399	154	10	INTERMEDIARIO	320	t	f
8400	154	64	INTERMEDIARIO	320	t	f
8401	154	72	INTERMEDIARIO	320	t	f
8402	154	82	INTERMEDIARIO	320	t	f
8403	154	112	AVANCADO	321	t	f
8404	98	103	INTERMEDIARIO	320	t	f
8405	98	104	BASICO	318	t	f
8406	98	49	BASICO	318	t	f
8407	98	50	BASICO	318	t	f
8408	98	51	BASICO	318	t	f
8409	98	52	BASICO	318	t	f
8410	98	16	BASICO	318	t	f
8411	98	21	BASICO	318	t	f
8412	98	55	INTERMEDIARIO	320	t	f
8413	98	56	INTERMEDIARIO	320	t	f
8414	98	58	INTERMEDIARIO	320	t	f
8415	98	61	BASICO	318	t	f
8416	98	117	BASICO	318	t	f
8417	98	72	BASICO	318	t	f
8418	205	35	BASICO	318	t	f
8419	205	36	BASICO	318	t	f
8420	205	16	BASICO	318	t	f
8421	205	20	BASICO	318	t	f
8422	205	21	BASICO	318	t	f
8423	205	58	BASICO	318	t	f
8424	205	72	INTERMEDIARIO	320	t	f
8425	205	82	INTERMEDIARIO	320	t	f
8426	205	108	BASICO	318	t	f
8427	69	98	BASICO	318	t	f
8428	69	99	BASICO	318	t	f
8429	69	100	BASICO	318	t	f
8430	69	101	BASICO	318	t	f
8431	69	102	INTERMEDIARIO	320	t	f
8432	69	103	BASICO	318	t	f
8433	69	104	BASICO	318	t	f
8434	69	105	BASICO	318	t	f
8435	69	106	INTERMEDIARIO	320	t	f
8436	69	107	BASICO	318	t	f
8437	69	47	BASICO	318	t	f
8438	69	48	BASICO	318	t	f
8439	69	49	BASICO	318	t	f
8440	69	50	BASICO	318	t	f
8441	69	51	BASICO	318	t	f
8442	69	52	AVANCADO	321	t	f
8443	69	28	BASICO	318	t	f
8444	69	29	INTERMEDIARIO	320	t	f
8445	69	30	INTERMEDIARIO	320	t	f
8446	69	33	INTERMEDIARIO	320	t	f
8447	69	34	INTERMEDIARIO	320	t	f
8448	69	35	INTERMEDIARIO	320	t	f
8449	69	36	INTERMEDIARIO	320	t	f
8450	69	37	INTERMEDIARIO	320	t	f
8451	69	38	INTERMEDIARIO	320	t	f
8452	69	39	INTERMEDIARIO	320	t	f
8453	69	40	INTERMEDIARIO	320	t	f
8454	69	41	INTERMEDIARIO	320	t	f
8455	69	42	INTERMEDIARIO	320	t	f
8456	69	43	INTERMEDIARIO	320	t	f
8457	69	44	AVANCADO	321	t	f
8458	69	45	BASICO	318	t	f
8459	69	46	BASICO	318	t	f
8460	69	13	BASICO	318	t	f
8461	69	14	AVANCADO	321	t	f
8462	69	15	AVANCADO	321	t	f
8463	69	16	BASICO	318	t	f
8464	69	17	BASICO	318	t	f
8465	69	18	INTERMEDIARIO	320	t	f
8466	69	19	AVANCADO	321	t	f
8467	69	20	AVANCADO	321	t	f
8468	69	21	AVANCADO	321	t	f
8469	69	22	BASICO	318	t	f
8470	69	23	BASICO	318	t	f
8471	69	24	AVANCADO	321	t	f
8472	69	25	AVANCADO	321	t	f
8473	69	26	INTERMEDIARIO	320	t	f
8474	69	27	BASICO	318	t	f
8475	69	53	INTERMEDIARIO	320	t	f
8476	69	54	INTERMEDIARIO	320	t	f
8477	69	55	AVANCADO	321	t	f
8478	69	56	AVANCADO	321	t	f
8479	69	57	BASICO	318	t	f
8480	69	58	AVANCADO	321	t	f
8481	69	59	AVANCADO	321	t	f
8482	69	60	INTERMEDIARIO	320	t	f
8483	69	61	AVANCADO	321	t	f
8484	69	62	AVANCADO	321	t	f
8485	69	113	AVANCADO	321	t	f
8486	69	114	INTERMEDIARIO	320	t	f
8487	69	115	AVANCADO	321	t	f
8488	69	116	AVANCADO	321	t	f
8489	69	117	AVANCADO	321	t	f
8490	69	118	INTERMEDIARIO	320	t	f
8491	69	119	AVANCADO	321	t	f
8492	69	120	INTERMEDIARIO	320	t	f
8493	69	121	BASICO	318	t	f
8494	69	122	BASICO	318	t	f
8495	69	123	INTERMEDIARIO	320	t	f
8496	69	124	AVANCADO	321	t	f
8497	69	125	INTERMEDIARIO	320	t	f
8498	69	126	INTERMEDIARIO	320	t	f
8499	69	127	INTERMEDIARIO	320	t	f
8500	69	129	AVANCADO	321	t	f
8501	69	1	INTERMEDIARIO	320	t	f
8502	69	2	BASICO	318	t	f
8503	69	3	BASICO	318	t	f
8504	69	4	INTERMEDIARIO	320	t	f
8505	69	5	BASICO	318	t	f
8506	69	6	BASICO	318	t	f
8507	69	7	INTERMEDIARIO	320	t	f
8508	69	8	INTERMEDIARIO	320	t	f
8509	69	9	AVANCADO	321	t	f
8510	69	10	INTERMEDIARIO	320	t	f
8511	69	11	INTERMEDIARIO	320	t	f
8512	69	12	INTERMEDIARIO	320	t	f
8513	69	63	INTERMEDIARIO	320	t	f
8514	69	64	BASICO	318	t	f
8515	69	65	AVANCADO	321	t	f
8516	69	66	AVANCADO	321	t	f
8517	69	67	BASICO	318	t	f
8518	69	68	BASICO	318	t	f
8519	69	69	BASICO	318	t	f
8520	69	70	BASICO	318	t	f
8521	69	71	BASICO	318	t	f
8522	69	72	AVANCADO	321	t	f
8523	69	73	INTERMEDIARIO	320	t	f
8524	69	74	INTERMEDIARIO	320	t	f
8525	69	75	INTERMEDIARIO	320	t	f
8526	69	76	BASICO	318	t	f
8527	69	77	BASICO	318	t	f
8528	69	78	BASICO	318	t	f
8529	69	79	BASICO	318	t	f
8530	69	81	BASICO	318	t	f
8531	69	82	BASICO	318	t	f
8532	69	108	AVANCADO	321	t	f
8533	69	109	AVANCADO	321	t	f
8534	69	110	BASICO	318	t	f
8535	69	111	AVANCADO	321	t	f
8536	69	112	BASICO	318	t	f
8537	45	98	BASICO	318	t	f
8538	45	99	BASICO	318	t	f
8539	45	100	BASICO	318	t	f
8540	45	101	BASICO	318	t	f
8541	45	102	BASICO	318	t	f
8542	45	103	BASICO	318	t	f
8543	45	104	BASICO	318	t	f
8544	45	105	BASICO	318	t	f
8545	45	106	BASICO	318	t	f
8546	45	107	BASICO	318	t	f
8547	45	47	BASICO	318	t	f
8548	45	48	BASICO	318	t	f
8549	45	49	INTERMEDIARIO	320	t	f
8550	45	50	INTERMEDIARIO	320	t	f
8551	45	51	BASICO	318	t	f
8552	45	52	INTERMEDIARIO	320	t	f
8553	45	28	BASICO	318	t	f
8554	45	29	BASICO	318	t	f
8555	45	30	INTERMEDIARIO	320	t	f
8556	45	31	BASICO	318	t	f
8557	45	32	BASICO	318	t	f
8558	45	33	BASICO	318	t	f
8559	45	34	BASICO	318	t	f
8560	45	35	INTERMEDIARIO	320	t	f
8561	45	36	INTERMEDIARIO	320	t	f
8562	45	37	BASICO	318	t	f
8563	45	38	BASICO	318	t	f
8564	45	39	BASICO	318	t	f
8565	45	40	BASICO	318	t	f
8566	45	41	BASICO	318	t	f
8567	45	42	BASICO	318	t	f
8568	45	43	BASICO	318	t	f
8569	45	44	BASICO	318	t	f
8570	45	45	BASICO	318	t	f
8571	45	46	BASICO	318	t	f
8572	45	13	BASICO	318	t	f
8573	45	14	INTERMEDIARIO	320	t	f
8574	45	15	BASICO	318	t	f
8575	45	16	BASICO	318	t	f
8576	45	17	BASICO	318	t	f
8577	45	18	BASICO	318	t	f
8578	45	19	INTERMEDIARIO	320	t	f
8579	45	20	INTERMEDIARIO	320	t	f
8580	45	21	INTERMEDIARIO	320	t	f
8581	45	22	BASICO	318	t	f
8582	45	23	BASICO	318	t	f
8583	45	24	BASICO	318	t	f
8584	45	25	BASICO	318	t	f
8585	45	26	BASICO	318	t	f
8586	45	27	BASICO	318	t	f
8587	45	53	BASICO	318	t	f
8588	45	54	BASICO	318	t	f
8589	45	55	INTERMEDIARIO	320	t	f
8590	45	56	INTERMEDIARIO	320	t	f
8591	45	57	BASICO	318	t	f
8592	45	58	INTERMEDIARIO	320	t	f
8593	45	59	INTERMEDIARIO	320	t	f
8594	45	60	INTERMEDIARIO	320	t	f
8595	45	61	INTERMEDIARIO	320	t	f
8596	45	62	BASICO	318	t	f
8597	45	83	BASICO	318	t	f
8598	45	84	BASICO	318	t	f
8599	45	85	BASICO	318	t	f
8600	45	86	BASICO	318	t	f
8601	45	87	BASICO	318	t	f
8602	45	88	BASICO	318	t	f
8603	45	89	BASICO	318	t	f
8604	45	90	BASICO	318	t	f
8605	45	91	BASICO	318	t	f
8606	45	92	BASICO	318	t	f
8607	45	93	BASICO	318	t	f
8608	45	94	BASICO	318	t	f
8609	45	95	BASICO	318	t	f
8610	45	96	BASICO	318	t	f
8611	45	97	BASICO	318	t	f
8612	45	130	BASICO	318	t	f
8613	45	113	BASICO	318	t	f
8614	45	114	BASICO	318	t	f
8615	45	115	BASICO	318	t	f
8616	45	116	BASICO	318	t	f
8617	45	117	INTERMEDIARIO	320	t	f
8618	45	118	BASICO	318	t	f
8619	45	119	BASICO	318	t	f
8620	45	120	BASICO	318	t	f
8621	45	121	BASICO	318	t	f
8622	45	122	BASICO	318	t	f
8623	45	123	BASICO	318	t	f
8624	45	124	BASICO	318	t	f
8625	45	125	BASICO	318	t	f
8626	45	126	BASICO	318	t	f
8627	45	127	BASICO	318	t	f
8628	45	129	BASICO	318	t	f
8629	45	1	BASICO	318	t	f
8630	45	2	BASICO	318	t	f
8631	45	3	BASICO	318	t	f
8632	45	4	BASICO	318	t	f
8633	45	5	BASICO	318	t	f
8634	45	6	BASICO	318	t	f
8635	45	7	BASICO	318	t	f
8636	45	8	BASICO	318	t	f
8637	45	9	BASICO	318	t	f
8638	45	10	BASICO	318	t	f
8639	45	11	BASICO	318	t	f
8640	45	12	BASICO	318	t	f
8641	45	63	BASICO	318	t	f
8642	45	64	BASICO	318	t	f
8643	45	65	BASICO	318	t	f
8644	45	66	BASICO	318	t	f
8645	45	67	BASICO	318	t	f
8646	45	68	BASICO	318	t	f
8647	45	69	BASICO	318	t	f
8648	45	70	BASICO	318	t	f
8649	45	71	BASICO	318	t	f
8650	45	72	BASICO	318	t	f
8651	45	73	BASICO	318	t	f
8652	45	74	BASICO	318	t	f
8653	45	75	BASICO	318	t	f
8654	45	76	BASICO	318	t	f
8655	45	77	INTERMEDIARIO	320	t	f
8656	45	78	BASICO	318	t	f
8657	45	79	BASICO	318	t	f
8658	45	81	BASICO	318	t	f
8659	45	82	INTERMEDIARIO	320	t	f
8660	45	108	BASICO	318	t	f
8661	45	109	BASICO	318	t	f
8662	45	110	BASICO	318	t	f
8663	45	111	INTERMEDIARIO	320	t	f
8664	45	112	BASICO	318	t	f
8665	122	98	BASICO	318	t	f
8666	122	99	BASICO	318	t	f
8667	122	100	INTERMEDIARIO	320	t	f
8668	122	102	INTERMEDIARIO	320	t	f
8669	122	103	BASICO	318	t	f
8670	122	104	BASICO	318	t	f
8671	122	106	INTERMEDIARIO	320	t	f
8672	122	107	INTERMEDIARIO	320	t	f
8673	122	48	BASICO	318	t	f
8674	122	49	BASICO	318	t	f
8675	122	50	BASICO	318	t	f
8676	122	51	BASICO	318	t	f
8677	122	52	INTERMEDIARIO	320	t	f
8678	122	29	BASICO	318	t	f
8679	122	35	BASICO	318	t	f
8680	122	36	INTERMEDIARIO	320	t	f
8681	122	38	INTERMEDIARIO	320	t	f
8682	122	39	INTERMEDIARIO	320	t	f
8683	122	40	BASICO	318	t	f
8684	122	41	INTERMEDIARIO	320	t	f
8685	122	44	BASICO	318	t	f
8686	122	16	INTERMEDIARIO	320	t	f
8687	122	18	BASICO	318	t	f
8688	122	19	BASICO	318	t	f
8689	122	20	BASICO	318	t	f
8690	122	23	INTERMEDIARIO	320	t	f
8691	122	26	INTERMEDIARIO	320	t	f
8692	122	53	BASICO	318	t	f
8693	122	54	BASICO	318	t	f
8694	122	55	INTERMEDIARIO	320	t	f
8695	122	56	INTERMEDIARIO	320	t	f
8696	122	58	INTERMEDIARIO	320	t	f
8697	122	59	BASICO	318	t	f
8698	122	60	BASICO	318	t	f
8699	122	61	BASICO	318	t	f
8700	122	114	BASICO	318	t	f
8701	122	115	INTERMEDIARIO	320	t	f
8702	122	116	INTERMEDIARIO	320	t	f
8703	122	117	BASICO	318	t	f
8704	122	119	BASICO	318	t	f
8705	122	120	BASICO	318	t	f
8706	122	122	BASICO	318	t	f
8707	122	123	BASICO	318	t	f
8708	122	129	BASICO	318	t	f
8709	122	1	INTERMEDIARIO	320	t	f
8710	122	2	INTERMEDIARIO	320	t	f
8711	122	4	INTERMEDIARIO	320	t	f
8712	122	8	BASICO	318	t	f
8713	122	9	INTERMEDIARIO	320	t	f
8714	122	12	INTERMEDIARIO	320	t	f
8715	122	64	BASICO	318	t	f
8716	122	65	BASICO	318	t	f
8717	122	71	BASICO	318	t	f
8718	122	72	BASICO	318	t	f
8719	122	82	BASICO	318	t	f
8720	122	108	INTERMEDIARIO	320	t	f
8721	122	109	INTERMEDIARIO	320	t	f
8722	122	111	INTERMEDIARIO	320	t	f
8723	200	102	BASICO	318	t	f
8724	200	104	BASICO	318	t	f
8725	200	105	BASICO	318	t	f
8726	200	106	BASICO	318	t	f
8727	200	52	INTERMEDIARIO	320	t	f
8728	200	36	BASICO	318	t	f
8729	200	40	BASICO	318	t	f
8730	200	41	BASICO	318	t	f
8731	200	16	INTERMEDIARIO	320	t	f
8732	200	21	BASICO	318	t	f
8733	200	55	INTERMEDIARIO	320	t	f
8734	200	56	INTERMEDIARIO	320	t	f
8735	200	58	BASICO	318	t	f
8736	200	59	BASICO	318	t	f
8737	200	115	BASICO	318	t	f
8738	200	117	BASICO	318	t	f
8739	200	119	BASICO	318	t	f
8740	200	1	INTERMEDIARIO	320	t	f
8741	200	12	BASICO	318	t	f
8742	200	63	BASICO	318	t	f
8743	200	72	BASICO	318	t	f
8744	200	77	INTERMEDIARIO	320	t	f
8745	9	98	BASICO	318	t	f
8746	9	99	BASICO	318	t	f
8747	9	100	BASICO	318	t	f
8748	9	101	BASICO	318	t	f
8749	9	102	BASICO	318	t	f
8750	9	103	AVANCADO	321	t	f
8751	9	104	BASICO	318	t	f
8752	9	105	BASICO	318	t	f
8753	9	106	BASICO	318	t	f
8754	9	107	BASICO	318	t	f
8755	9	47	BASICO	318	t	f
8756	9	48	BASICO	318	t	f
8757	9	49	BASICO	318	t	f
8758	9	50	BASICO	318	t	f
8759	9	51	BASICO	318	t	f
8760	9	52	BASICO	318	t	f
8761	9	28	BASICO	318	t	f
8762	9	29	BASICO	318	t	f
8763	9	30	BASICO	318	t	f
8764	9	31	BASICO	318	t	f
8765	9	32	BASICO	318	t	f
8766	9	33	BASICO	318	t	f
8767	9	34	BASICO	318	t	f
8768	9	35	BASICO	318	t	f
8769	9	36	BASICO	318	t	f
8770	9	37	BASICO	318	t	f
8771	9	38	BASICO	318	t	f
8772	9	39	BASICO	318	t	f
8773	9	40	BASICO	318	t	f
8774	9	41	BASICO	318	t	f
8775	9	42	BASICO	318	t	f
8776	9	43	BASICO	318	t	f
8777	9	44	BASICO	318	t	f
8778	9	45	BASICO	318	t	f
8779	9	46	BASICO	318	t	f
8780	9	13	BASICO	318	t	f
8781	9	14	BASICO	318	t	f
8782	9	15	BASICO	318	t	f
8783	9	16	BASICO	318	t	f
8784	9	17	BASICO	318	t	f
8785	9	18	BASICO	318	t	f
8786	9	19	BASICO	318	t	f
8787	9	20	BASICO	318	t	f
8788	9	21	BASICO	318	t	f
8789	9	22	BASICO	318	t	f
8790	9	23	BASICO	318	t	f
8791	9	24	BASICO	318	t	f
8792	9	25	BASICO	318	t	f
8793	9	26	BASICO	318	t	f
8794	9	27	BASICO	318	t	f
8795	9	53	BASICO	318	t	f
8796	9	54	BASICO	318	t	f
8797	9	55	BASICO	318	t	f
8798	9	56	BASICO	318	t	f
8799	9	57	BASICO	318	t	f
8800	9	58	BASICO	318	t	f
8801	9	59	BASICO	318	t	f
8802	9	60	BASICO	318	t	f
8803	9	61	BASICO	318	t	f
8804	9	62	BASICO	318	t	f
8805	9	83	BASICO	318	t	f
8806	9	84	BASICO	318	t	f
8807	9	85	BASICO	318	t	f
8808	9	86	BASICO	318	t	f
8809	9	87	BASICO	318	t	f
8810	9	88	BASICO	318	t	f
8811	9	89	BASICO	318	t	f
8812	9	90	BASICO	318	t	f
8813	9	91	BASICO	318	t	f
8814	9	92	BASICO	318	t	f
8815	9	93	BASICO	318	t	f
8816	9	94	BASICO	318	t	f
8817	9	95	BASICO	318	t	f
8818	9	96	BASICO	318	t	f
8819	9	97	BASICO	318	t	f
8820	9	130	BASICO	318	t	f
8821	9	113	BASICO	318	t	f
8822	9	114	BASICO	318	t	f
8823	9	115	BASICO	318	t	f
8824	9	116	BASICO	318	t	f
8825	9	117	BASICO	318	t	f
8826	9	118	BASICO	318	t	f
8827	9	119	BASICO	318	t	f
8828	9	120	BASICO	318	t	f
8829	9	121	BASICO	318	t	f
8830	9	122	BASICO	318	t	f
8831	9	123	BASICO	318	t	f
8832	9	124	BASICO	318	t	f
8833	9	125	BASICO	318	t	f
8834	9	126	BASICO	318	t	f
8835	9	127	BASICO	318	t	f
8836	9	129	BASICO	318	t	f
8837	9	1	BASICO	318	t	f
8838	9	2	BASICO	318	t	f
8839	9	3	BASICO	318	t	f
8840	9	4	BASICO	318	t	f
8841	9	5	BASICO	318	t	f
8842	9	6	BASICO	318	t	f
8843	9	7	BASICO	318	t	f
8844	9	8	BASICO	318	t	f
8845	9	9	BASICO	318	t	f
8846	9	10	BASICO	318	t	f
8847	9	11	BASICO	318	t	f
8848	9	12	BASICO	318	t	f
8849	9	63	BASICO	318	t	f
8850	9	64	BASICO	318	t	f
8851	9	65	BASICO	318	t	f
8852	9	66	BASICO	318	t	f
8853	9	67	BASICO	318	t	f
8854	9	68	BASICO	318	t	f
8855	9	69	BASICO	318	t	f
8856	9	70	BASICO	318	t	f
8857	9	71	BASICO	318	t	f
8858	9	72	BASICO	318	t	f
8859	9	73	BASICO	318	t	f
8860	9	74	BASICO	318	t	f
8861	9	75	BASICO	318	t	f
8862	9	76	BASICO	318	t	f
8863	9	77	BASICO	318	t	f
8864	9	78	BASICO	318	t	f
8865	9	79	BASICO	318	t	f
8866	9	81	BASICO	318	t	f
8867	9	82	BASICO	318	t	f
8868	9	108	BASICO	318	t	f
8869	9	109	BASICO	318	t	f
8870	9	110	BASICO	318	t	f
8871	9	111	BASICO	318	t	f
8872	9	112	BASICO	318	t	f
8873	233	98	BASICO	318	t	f
8874	233	99	INTERMEDIARIO	320	t	f
8875	233	100	BASICO	318	t	f
8876	233	101	BASICO	318	t	f
8877	233	102	AVANCADO	321	t	f
8878	233	103	INTERMEDIARIO	320	t	f
8879	233	104	BASICO	318	t	f
8880	233	105	AVANCADO	321	t	f
8881	233	106	INTERMEDIARIO	320	t	f
8882	233	107	INTERMEDIARIO	320	t	f
8883	233	47	BASICO	318	t	f
8884	233	48	INTERMEDIARIO	320	t	f
8885	233	49	BASICO	318	t	f
8886	233	50	AVANCADO	321	t	f
8887	233	51	BASICO	318	t	f
8888	233	52	INTERMEDIARIO	320	t	f
8889	233	28	BASICO	318	t	f
8890	233	29	INTERMEDIARIO	320	t	f
8891	233	30	INTERMEDIARIO	320	t	f
8892	233	31	BASICO	318	t	f
8893	233	32	BASICO	318	t	f
8894	233	33	BASICO	318	t	f
8895	233	34	INTERMEDIARIO	320	t	f
8896	233	35	BASICO	318	t	f
8897	233	36	INTERMEDIARIO	320	t	f
8898	233	38	INTERMEDIARIO	320	t	f
8899	233	39	BASICO	318	t	f
8900	233	40	INTERMEDIARIO	320	t	f
8901	233	41	INTERMEDIARIO	320	t	f
8902	233	42	BASICO	318	t	f
8903	233	43	BASICO	318	t	f
8904	233	44	BASICO	318	t	f
8905	233	45	BASICO	318	t	f
8906	233	46	BASICO	318	t	f
8907	233	13	INTERMEDIARIO	320	t	f
8908	233	14	INTERMEDIARIO	320	t	f
8909	233	15	INTERMEDIARIO	320	t	f
8910	233	16	BASICO	318	t	f
8911	233	17	BASICO	318	t	f
8912	233	18	BASICO	318	t	f
8913	233	19	INTERMEDIARIO	320	t	f
8914	233	20	INTERMEDIARIO	320	t	f
8915	233	21	INTERMEDIARIO	320	t	f
8916	233	22	BASICO	318	t	f
8917	233	23	BASICO	318	t	f
8918	233	24	BASICO	318	t	f
8919	233	25	INTERMEDIARIO	320	t	f
8920	233	26	INTERMEDIARIO	320	t	f
8921	233	27	BASICO	318	t	f
8922	233	53	INTERMEDIARIO	320	t	f
8923	233	54	BASICO	318	t	f
8924	233	55	INTERMEDIARIO	320	t	f
8925	233	56	INTERMEDIARIO	320	t	f
8926	233	57	BASICO	318	t	f
8927	233	58	INTERMEDIARIO	320	t	f
8928	233	59	INTERMEDIARIO	320	t	f
8929	233	60	BASICO	318	t	f
8930	233	61	INTERMEDIARIO	320	t	f
8931	233	62	BASICO	318	t	f
8932	233	83	BASICO	318	t	f
8933	233	84	BASICO	318	t	f
8934	233	85	INTERMEDIARIO	320	t	f
8935	233	86	BASICO	318	t	f
8936	233	87	BASICO	318	t	f
8937	233	88	BASICO	318	t	f
8938	233	89	BASICO	318	t	f
8939	233	90	BASICO	318	t	f
8940	233	91	INTERMEDIARIO	320	t	f
8941	233	92	BASICO	318	t	f
8942	233	93	BASICO	318	t	f
8943	233	94	INTERMEDIARIO	320	t	f
8944	233	95	BASICO	318	t	f
8945	233	96	INTERMEDIARIO	320	t	f
8946	233	97	INTERMEDIARIO	320	t	f
8947	233	130	BASICO	318	t	f
8948	233	113	BASICO	318	t	f
8949	233	114	BASICO	318	t	f
8950	233	115	BASICO	318	t	f
8951	233	116	BASICO	318	t	f
8952	233	117	INTERMEDIARIO	320	t	f
8953	233	118	BASICO	318	t	f
8954	233	119	INTERMEDIARIO	320	t	f
8955	233	120	BASICO	318	t	f
8956	233	121	BASICO	318	t	f
8957	233	122	BASICO	318	t	f
8958	233	123	BASICO	318	t	f
8959	233	124	BASICO	318	t	f
8960	233	125	BASICO	318	t	f
8961	233	126	BASICO	318	t	f
8962	233	127	BASICO	318	t	f
8963	233	129	BASICO	318	t	f
8964	233	1	INTERMEDIARIO	320	t	f
8965	233	2	BASICO	318	t	f
8966	233	3	BASICO	318	t	f
8967	233	4	BASICO	318	t	f
8968	233	5	BASICO	318	t	f
8969	233	6	BASICO	318	t	f
8970	233	7	BASICO	318	t	f
8971	233	8	BASICO	318	t	f
8972	233	9	BASICO	318	t	f
8973	233	10	BASICO	318	t	f
8974	233	11	BASICO	318	t	f
8975	233	12	INTERMEDIARIO	320	t	f
8976	233	63	INTERMEDIARIO	320	t	f
8977	233	64	INTERMEDIARIO	320	t	f
8978	233	65	BASICO	318	t	f
8979	233	66	BASICO	318	t	f
8980	233	67	BASICO	318	t	f
8981	233	68	BASICO	318	t	f
8982	233	69	BASICO	318	t	f
8983	233	70	BASICO	318	t	f
8984	233	71	INTERMEDIARIO	320	t	f
8985	233	72	INTERMEDIARIO	320	t	f
8986	233	73	BASICO	318	t	f
8987	233	74	BASICO	318	t	f
8988	233	75	BASICO	318	t	f
8989	233	76	BASICO	318	t	f
8990	233	77	BASICO	318	t	f
8991	233	78	BASICO	318	t	f
8992	233	79	BASICO	318	t	f
8993	233	81	BASICO	318	t	f
8994	233	82	INTERMEDIARIO	320	t	f
8995	233	108	INTERMEDIARIO	320	t	f
8996	233	109	BASICO	318	t	f
8997	233	110	INTERMEDIARIO	320	t	f
8998	233	111	INTERMEDIARIO	320	t	f
8999	233	112	BASICO	318	t	f
9000	22	98	BASICO	318	t	f
9001	22	99	BASICO	318	t	f
9002	22	100	BASICO	318	t	f
9003	22	101	BASICO	318	t	f
9004	22	103	INTERMEDIARIO	320	t	f
9005	22	104	BASICO	318	t	f
9006	22	105	BASICO	318	t	f
9007	22	106	BASICO	318	t	f
9008	22	107	BASICO	318	t	f
9009	22	47	BASICO	318	t	f
9010	22	48	BASICO	318	t	f
9011	22	49	BASICO	318	t	f
9012	22	50	BASICO	318	t	f
9013	22	51	BASICO	318	t	f
9014	22	52	BASICO	318	t	f
9015	22	28	BASICO	318	t	f
9016	22	29	BASICO	318	t	f
9017	22	30	BASICO	318	t	f
9018	22	31	BASICO	318	t	f
9019	22	32	BASICO	318	t	f
9020	22	33	BASICO	318	t	f
9021	22	34	BASICO	318	t	f
9022	22	35	BASICO	318	t	f
9023	22	36	BASICO	318	t	f
9024	22	37	BASICO	318	t	f
9025	22	38	BASICO	318	t	f
9026	22	39	BASICO	318	t	f
9027	22	40	BASICO	318	t	f
9028	22	41	BASICO	318	t	f
9029	22	42	BASICO	318	t	f
9030	22	43	BASICO	318	t	f
9031	22	44	BASICO	318	t	f
9032	22	45	BASICO	318	t	f
9033	22	46	BASICO	318	t	f
9034	22	13	BASICO	318	t	f
9035	22	14	BASICO	318	t	f
9036	22	16	INTERMEDIARIO	320	t	f
9037	22	17	BASICO	318	t	f
9038	22	18	BASICO	318	t	f
9039	22	19	BASICO	318	t	f
9040	22	20	BASICO	318	t	f
9041	22	21	BASICO	318	t	f
9042	22	22	BASICO	318	t	f
9043	22	23	BASICO	318	t	f
9044	22	24	BASICO	318	t	f
9045	22	25	BASICO	318	t	f
9046	22	26	BASICO	318	t	f
9047	22	27	BASICO	318	t	f
9048	22	53	BASICO	318	t	f
9049	22	54	BASICO	318	t	f
9050	22	55	BASICO	318	t	f
9051	22	56	INTERMEDIARIO	320	t	f
9052	22	57	BASICO	318	t	f
9053	22	58	INTERMEDIARIO	320	t	f
9054	22	59	BASICO	318	t	f
9055	22	60	BASICO	318	t	f
9056	22	61	BASICO	318	t	f
9057	22	62	BASICO	318	t	f
9058	22	83	BASICO	318	t	f
9059	22	84	BASICO	318	t	f
9060	22	85	BASICO	318	t	f
9061	22	86	BASICO	318	t	f
9062	22	87	BASICO	318	t	f
9063	22	88	BASICO	318	t	f
9064	22	89	BASICO	318	t	f
9065	22	90	BASICO	318	t	f
9066	22	91	BASICO	318	t	f
9067	22	92	BASICO	318	t	f
9068	22	93	BASICO	318	t	f
9069	22	94	BASICO	318	t	f
9070	22	95	BASICO	318	t	f
9071	22	96	BASICO	318	t	f
9072	22	97	BASICO	318	t	f
9073	22	130	BASICO	318	t	f
9074	22	113	BASICO	318	t	f
9075	22	114	BASICO	318	t	f
9076	22	115	BASICO	318	t	f
9077	22	116	BASICO	318	t	f
9078	22	117	BASICO	318	t	f
9079	22	118	BASICO	318	t	f
9080	22	119	BASICO	318	t	f
9081	22	120	BASICO	318	t	f
9082	22	121	BASICO	318	t	f
9083	22	122	BASICO	318	t	f
9084	22	123	BASICO	318	t	f
9085	22	124	BASICO	318	t	f
9086	22	125	BASICO	318	t	f
9087	22	126	BASICO	318	t	f
9088	22	127	BASICO	318	t	f
9089	22	129	BASICO	318	t	f
9090	22	1	BASICO	318	t	f
9091	22	2	BASICO	318	t	f
9092	22	3	BASICO	318	t	f
9093	22	4	BASICO	318	t	f
9094	22	5	BASICO	318	t	f
9095	22	6	BASICO	318	t	f
9096	22	7	BASICO	318	t	f
9097	22	8	BASICO	318	t	f
9098	22	9	BASICO	318	t	f
9099	22	10	BASICO	318	t	f
9100	22	11	BASICO	318	t	f
9101	22	12	BASICO	318	t	f
9102	22	63	BASICO	318	t	f
9103	22	64	BASICO	318	t	f
9104	22	65	BASICO	318	t	f
9105	22	66	BASICO	318	t	f
9106	22	67	BASICO	318	t	f
9107	22	68	BASICO	318	t	f
9108	22	69	BASICO	318	t	f
9109	22	70	BASICO	318	t	f
9110	22	71	BASICO	318	t	f
9111	22	72	BASICO	318	t	f
9112	22	73	BASICO	318	t	f
9113	22	74	BASICO	318	t	f
9114	22	75	BASICO	318	t	f
9115	22	76	BASICO	318	t	f
9116	22	77	BASICO	318	t	f
9117	22	78	BASICO	318	t	f
9118	22	79	BASICO	318	t	f
9119	22	81	BASICO	318	t	f
9120	22	82	BASICO	318	t	f
9121	22	108	BASICO	318	t	f
9122	22	109	BASICO	318	t	f
9123	22	110	BASICO	318	t	f
9124	22	111	BASICO	318	t	f
9125	22	112	BASICO	318	t	f
9126	217	102	BASICO	318	t	f
9127	217	104	BASICO	318	t	f
9128	217	106	BASICO	318	t	f
9129	217	107	BASICO	318	t	f
9130	217	49	BASICO	318	t	f
9131	217	50	BASICO	318	t	f
9132	217	51	BASICO	318	t	f
9133	217	52	BASICO	318	t	f
9134	217	28	BASICO	318	t	f
9135	217	29	BASICO	318	t	f
9136	217	30	BASICO	318	t	f
9137	217	33	BASICO	318	t	f
9138	217	34	BASICO	318	t	f
9139	217	36	BASICO	318	t	f
9140	217	38	BASICO	318	t	f
9141	217	40	BASICO	318	t	f
9142	217	43	BASICO	318	t	f
9143	217	14	BASICO	318	t	f
9144	217	19	BASICO	318	t	f
9145	217	20	BASICO	318	t	f
9146	217	21	BASICO	318	t	f
9147	217	55	BASICO	318	t	f
9148	217	56	BASICO	318	t	f
9149	217	58	BASICO	318	t	f
9150	217	113	BASICO	318	t	f
9151	217	115	BASICO	318	t	f
9152	217	117	BASICO	318	t	f
9153	217	119	BASICO	318	t	f
9154	217	122	BASICO	318	t	f
9155	217	123	BASICO	318	t	f
9156	217	129	BASICO	318	t	f
9157	217	12	BASICO	318	t	f
9158	217	63	BASICO	318	t	f
9159	217	64	BASICO	318	t	f
9160	217	65	BASICO	318	t	f
9161	217	71	BASICO	318	t	f
9162	217	72	BASICO	318	t	f
9163	217	73	BASICO	318	t	f
9164	217	77	BASICO	318	t	f
9165	217	82	BASICO	318	t	f
9166	217	108	BASICO	318	t	f
9167	70	104	BASICO	318	t	f
9168	70	105	BASICO	318	t	f
9169	70	106	BASICO	318	t	f
9170	70	49	BASICO	318	t	f
9171	70	50	BASICO	318	t	f
9172	70	52	BASICO	318	t	f
9173	70	29	BASICO	318	t	f
9174	70	30	BASICO	318	t	f
9175	70	34	BASICO	318	t	f
9176	70	36	INTERMEDIARIO	320	t	f
9177	70	37	BASICO	318	t	f
9178	70	40	BASICO	318	t	f
9179	70	43	INTERMEDIARIO	320	t	f
9180	70	14	BASICO	318	t	f
9181	70	15	INTERMEDIARIO	320	t	f
9182	70	27	BASICO	318	t	f
9183	70	55	INTERMEDIARIO	320	t	f
9184	70	56	INTERMEDIARIO	320	t	f
9185	70	57	BASICO	318	t	f
9186	70	58	INTERMEDIARIO	320	t	f
9187	70	61	INTERMEDIARIO	320	t	f
9188	70	84	BASICO	318	t	f
9189	70	89	BASICO	318	t	f
9190	70	94	BASICO	318	t	f
9191	70	114	BASICO	318	t	f
9192	70	116	BASICO	318	t	f
9193	70	117	BASICO	318	t	f
9194	70	120	BASICO	318	t	f
9195	70	129	BASICO	318	t	f
9196	70	1	INTERMEDIARIO	320	t	f
9197	70	4	INTERMEDIARIO	320	t	f
9198	70	7	BASICO	318	t	f
9199	70	8	BASICO	318	t	f
9200	70	9	INTERMEDIARIO	320	t	f
9201	70	12	BASICO	318	t	f
9202	70	63	BASICO	318	t	f
9203	70	66	BASICO	318	t	f
9204	70	72	BASICO	318	t	f
9205	70	75	BASICO	318	t	f
9206	70	108	BASICO	318	t	f
9207	70	109	BASICO	318	t	f
9208	70	110	BASICO	318	t	f
9209	70	111	BASICO	318	t	f
9210	44	98	INTERMEDIARIO	320	t	f
9211	44	99	BASICO	318	t	f
9212	44	100	BASICO	318	t	f
9213	44	101	BASICO	318	t	f
9214	44	102	INTERMEDIARIO	320	t	f
9215	44	103	BASICO	318	t	f
9216	44	104	BASICO	318	t	f
9217	44	105	INTERMEDIARIO	320	t	f
9218	44	106	BASICO	318	t	f
9219	44	47	BASICO	318	t	f
9220	44	48	BASICO	318	t	f
9221	44	49	INTERMEDIARIO	320	t	f
9222	44	50	INTERMEDIARIO	320	t	f
9223	44	51	INTERMEDIARIO	320	t	f
9224	44	52	BASICO	318	t	f
9225	44	28	BASICO	318	t	f
9226	44	29	BASICO	318	t	f
9227	44	30	BASICO	318	t	f
9228	44	31	BASICO	318	t	f
9229	44	32	BASICO	318	t	f
9230	44	33	BASICO	318	t	f
9231	44	34	BASICO	318	t	f
9232	44	35	BASICO	318	t	f
9233	44	36	INTERMEDIARIO	320	t	f
9234	44	37	BASICO	318	t	f
9235	44	38	BASICO	318	t	f
9236	44	39	BASICO	318	t	f
9237	44	40	BASICO	318	t	f
9238	44	41	BASICO	318	t	f
9239	44	42	BASICO	318	t	f
9240	44	43	BASICO	318	t	f
9241	44	44	BASICO	318	t	f
9242	44	45	BASICO	318	t	f
9243	44	46	BASICO	318	t	f
9244	44	13	BASICO	318	t	f
9245	44	14	BASICO	318	t	f
9246	44	15	BASICO	318	t	f
9247	44	16	INTERMEDIARIO	320	t	f
9248	44	17	BASICO	318	t	f
9249	44	18	BASICO	318	t	f
9250	44	19	BASICO	318	t	f
9251	44	20	BASICO	318	t	f
9252	44	21	BASICO	318	t	f
9253	44	22	BASICO	318	t	f
9254	44	23	BASICO	318	t	f
9255	44	24	BASICO	318	t	f
9256	44	25	BASICO	318	t	f
9257	44	26	BASICO	318	t	f
9258	44	27	BASICO	318	t	f
9259	44	53	BASICO	318	t	f
9260	44	54	BASICO	318	t	f
9261	44	55	BASICO	318	t	f
9262	44	56	BASICO	318	t	f
9263	44	57	BASICO	318	t	f
9264	44	58	BASICO	318	t	f
9265	44	59	BASICO	318	t	f
9266	44	60	BASICO	318	t	f
9267	44	61	BASICO	318	t	f
9268	44	62	BASICO	318	t	f
9269	44	83	BASICO	318	t	f
9270	44	84	BASICO	318	t	f
9271	44	85	BASICO	318	t	f
9272	44	86	BASICO	318	t	f
9273	44	87	BASICO	318	t	f
9274	44	88	BASICO	318	t	f
9275	44	89	BASICO	318	t	f
9276	44	90	BASICO	318	t	f
9277	44	91	BASICO	318	t	f
9278	44	92	BASICO	318	t	f
9279	44	93	BASICO	318	t	f
9280	44	94	BASICO	318	t	f
9281	44	95	BASICO	318	t	f
9282	44	96	BASICO	318	t	f
9283	44	97	BASICO	318	t	f
9284	44	130	BASICO	318	t	f
9285	44	113	BASICO	318	t	f
9286	44	114	BASICO	318	t	f
9287	44	115	BASICO	318	t	f
9288	44	116	BASICO	318	t	f
9289	44	117	BASICO	318	t	f
9290	44	118	BASICO	318	t	f
9291	44	119	BASICO	318	t	f
9292	44	120	BASICO	318	t	f
9293	44	121	BASICO	318	t	f
9294	44	122	BASICO	318	t	f
9295	44	123	BASICO	318	t	f
9296	44	124	BASICO	318	t	f
9297	44	125	BASICO	318	t	f
9298	44	126	BASICO	318	t	f
9299	44	127	BASICO	318	t	f
9300	44	129	BASICO	318	t	f
9301	44	1	BASICO	318	t	f
9302	44	2	BASICO	318	t	f
9303	44	3	BASICO	318	t	f
9304	44	4	BASICO	318	t	f
9305	44	5	BASICO	318	t	f
9306	44	6	BASICO	318	t	f
9307	44	7	BASICO	318	t	f
9308	44	8	BASICO	318	t	f
9309	44	9	BASICO	318	t	f
9310	44	10	BASICO	318	t	f
9311	44	11	BASICO	318	t	f
9312	44	12	BASICO	318	t	f
9313	44	63	BASICO	318	t	f
9314	44	64	BASICO	318	t	f
9315	44	65	BASICO	318	t	f
9316	44	66	BASICO	318	t	f
9317	44	67	BASICO	318	t	f
9318	44	68	BASICO	318	t	f
9319	44	69	BASICO	318	t	f
9320	44	70	BASICO	318	t	f
9321	44	71	BASICO	318	t	f
9322	44	72	BASICO	318	t	f
9323	44	73	BASICO	318	t	f
9324	44	74	BASICO	318	t	f
9325	44	75	BASICO	318	t	f
9326	44	76	BASICO	318	t	f
9327	44	77	BASICO	318	t	f
9328	44	78	INTERMEDIARIO	320	t	f
9329	44	79	BASICO	318	t	f
9330	44	81	BASICO	318	t	f
9331	44	82	BASICO	318	t	f
9332	44	108	BASICO	318	t	f
9333	44	109	BASICO	318	t	f
9334	44	110	BASICO	318	t	f
9335	44	111	BASICO	318	t	f
9336	44	112	BASICO	318	t	f
9337	37	107	INTERMEDIARIO	320	t	f
9338	37	49	AVANCADO	321	t	f
9339	37	50	AVANCADO	321	t	f
9340	37	52	AVANCADO	321	t	f
9341	37	29	AVANCADO	321	t	f
9342	37	33	AVANCADO	321	t	f
9343	37	36	AVANCADO	321	t	f
9344	37	37	AVANCADO	321	t	f
9345	37	38	AVANCADO	321	t	f
9346	37	39	AVANCADO	321	t	f
9347	37	40	AVANCADO	321	t	f
9348	37	41	AVANCADO	321	t	f
9349	37	43	AVANCADO	321	t	f
9350	37	44	AVANCADO	321	t	f
9351	37	14	AVANCADO	321	t	f
9352	37	15	AVANCADO	321	t	f
9353	37	16	AVANCADO	321	t	f
9354	37	18	AVANCADO	321	t	f
9355	37	19	AVANCADO	321	t	f
9356	37	20	AVANCADO	321	t	f
9357	37	21	AVANCADO	321	t	f
9358	37	27	AVANCADO	321	t	f
9359	37	55	AVANCADO	321	t	f
9360	37	56	AVANCADO	321	t	f
9361	37	58	AVANCADO	321	t	f
9362	37	59	AVANCADO	321	t	f
9363	37	60	AVANCADO	321	t	f
9364	37	61	AVANCADO	321	t	f
9365	37	84	AVANCADO	321	t	f
9366	37	89	AVANCADO	321	t	f
9367	37	94	AVANCADO	321	t	f
9368	37	113	AVANCADO	321	t	f
9369	37	114	AVANCADO	321	t	f
9370	37	115	AVANCADO	321	t	f
9371	37	116	AVANCADO	321	t	f
9372	37	117	AVANCADO	321	t	f
9373	37	119	AVANCADO	321	t	f
9374	37	123	AVANCADO	321	t	f
9375	37	124	AVANCADO	321	t	f
9376	37	129	AVANCADO	321	t	f
9377	37	1	AVANCADO	321	t	f
9378	37	2	AVANCADO	321	t	f
9379	37	3	AVANCADO	321	t	f
9380	37	4	AVANCADO	321	t	f
9381	37	7	AVANCADO	321	t	f
9382	37	8	AVANCADO	321	t	f
9383	37	9	AVANCADO	321	t	f
9384	37	11	AVANCADO	321	t	f
9385	37	12	AVANCADO	321	t	f
9386	37	65	AVANCADO	321	t	f
9387	37	66	AVANCADO	321	t	f
9388	37	67	AVANCADO	321	t	f
9389	37	71	AVANCADO	321	t	f
9390	37	72	AVANCADO	321	t	f
9391	37	73	AVANCADO	321	t	f
9392	37	74	AVANCADO	321	t	f
9393	37	75	AVANCADO	321	t	f
9394	37	82	AVANCADO	321	t	f
9395	37	108	AVANCADO	321	t	f
9396	37	109	AVANCADO	321	t	f
9397	37	111	AVANCADO	321	t	f
9398	132	98	BASICO	318	t	f
9399	132	99	BASICO	318	t	f
9400	132	100	BASICO	318	t	f
9401	132	101	BASICO	318	t	f
9402	132	102	BASICO	318	t	f
9403	132	103	BASICO	318	t	f
9404	132	104	BASICO	318	t	f
9405	132	105	BASICO	318	t	f
9406	132	106	BASICO	318	t	f
9407	132	107	BASICO	318	t	f
9408	132	47	BASICO	318	t	f
9409	132	48	BASICO	318	t	f
9410	132	49	BASICO	318	t	f
9411	132	50	BASICO	318	t	f
9412	132	51	BASICO	318	t	f
9413	132	52	BASICO	318	t	f
9414	132	28	BASICO	318	t	f
9415	132	29	BASICO	318	t	f
9416	132	30	BASICO	318	t	f
9417	132	31	BASICO	318	t	f
9418	132	32	BASICO	318	t	f
9419	132	33	BASICO	318	t	f
9420	132	34	BASICO	318	t	f
9421	132	35	BASICO	318	t	f
9422	132	36	BASICO	318	t	f
9423	132	37	BASICO	318	t	f
9424	132	38	BASICO	318	t	f
9425	132	39	BASICO	318	t	f
9426	132	40	BASICO	318	t	f
9427	132	41	BASICO	318	t	f
9428	132	42	BASICO	318	t	f
9429	132	43	BASICO	318	t	f
9430	132	44	BASICO	318	t	f
9431	132	45	BASICO	318	t	f
9432	132	46	BASICO	318	t	f
9433	132	13	BASICO	318	t	f
9434	132	14	BASICO	318	t	f
9435	132	15	BASICO	318	t	f
9436	132	16	BASICO	318	t	f
9437	132	17	BASICO	318	t	f
9438	132	18	BASICO	318	t	f
9439	132	19	BASICO	318	t	f
9440	132	20	BASICO	318	t	f
9441	132	21	BASICO	318	t	f
9442	132	22	BASICO	318	t	f
9443	132	23	BASICO	318	t	f
9444	132	24	BASICO	318	t	f
9445	132	25	BASICO	318	t	f
9446	132	26	BASICO	318	t	f
9447	132	27	BASICO	318	t	f
9448	132	53	BASICO	318	t	f
9449	132	54	BASICO	318	t	f
9450	132	55	BASICO	318	t	f
9451	132	56	BASICO	318	t	f
9452	132	57	BASICO	318	t	f
9453	132	58	BASICO	318	t	f
9454	132	59	BASICO	318	t	f
9455	132	60	BASICO	318	t	f
9456	132	61	BASICO	318	t	f
9457	132	62	BASICO	318	t	f
9458	132	83	BASICO	318	t	f
9459	132	84	BASICO	318	t	f
9460	132	85	BASICO	318	t	f
9461	132	86	BASICO	318	t	f
9462	132	87	BASICO	318	t	f
9463	132	88	BASICO	318	t	f
9464	132	89	BASICO	318	t	f
9465	132	90	BASICO	318	t	f
9466	132	91	BASICO	318	t	f
9467	132	92	BASICO	318	t	f
9468	132	93	BASICO	318	t	f
9469	132	94	BASICO	318	t	f
9470	132	95	BASICO	318	t	f
9471	132	96	BASICO	318	t	f
9472	132	97	BASICO	318	t	f
9473	132	130	BASICO	318	t	f
9474	132	113	BASICO	318	t	f
9475	132	114	BASICO	318	t	f
9476	132	115	BASICO	318	t	f
9477	132	116	BASICO	318	t	f
9478	132	117	BASICO	318	t	f
9479	132	118	BASICO	318	t	f
9480	132	119	BASICO	318	t	f
9481	132	120	BASICO	318	t	f
9482	132	121	BASICO	318	t	f
9483	132	122	BASICO	318	t	f
9484	132	123	BASICO	318	t	f
9485	132	124	BASICO	318	t	f
9486	132	125	BASICO	318	t	f
9487	132	126	BASICO	318	t	f
9488	132	127	BASICO	318	t	f
9489	132	129	BASICO	318	t	f
9490	132	1	BASICO	318	t	f
9491	132	2	BASICO	318	t	f
9492	132	3	BASICO	318	t	f
9493	132	4	BASICO	318	t	f
9494	132	5	BASICO	318	t	f
9495	132	6	BASICO	318	t	f
9496	132	7	BASICO	318	t	f
9497	132	8	BASICO	318	t	f
9498	132	9	BASICO	318	t	f
9499	132	10	BASICO	318	t	f
9500	132	11	BASICO	318	t	f
9501	132	12	BASICO	318	t	f
9502	132	63	BASICO	318	t	f
9503	132	64	BASICO	318	t	f
9504	132	65	BASICO	318	t	f
9505	132	66	BASICO	318	t	f
9506	132	67	BASICO	318	t	f
9507	132	68	BASICO	318	t	f
9508	132	69	BASICO	318	t	f
9509	132	70	BASICO	318	t	f
9510	132	71	BASICO	318	t	f
9511	132	72	BASICO	318	t	f
9512	132	73	BASICO	318	t	f
9513	132	74	BASICO	318	t	f
9514	132	75	BASICO	318	t	f
9515	132	76	BASICO	318	t	f
9516	132	77	BASICO	318	t	f
9517	132	78	BASICO	318	t	f
9518	132	79	BASICO	318	t	f
9519	132	81	BASICO	318	t	f
9520	132	82	BASICO	318	t	f
9521	132	108	BASICO	318	t	f
9522	132	109	BASICO	318	t	f
9523	132	110	BASICO	318	t	f
9524	132	111	BASICO	318	t	f
9525	132	112	BASICO	318	t	f
9526	32	103	BASICO	318	t	f
9527	311	98	BASICO	318	t	f
9528	311	99	INTERMEDIARIO	320	t	f
9529	311	100	BASICO	318	t	f
9530	311	101	INTERMEDIARIO	320	t	f
9531	311	102	INTERMEDIARIO	320	t	f
9532	311	103	INTERMEDIARIO	320	t	f
9533	311	104	INTERMEDIARIO	320	t	f
9534	311	105	BASICO	318	t	f
9535	311	106	INTERMEDIARIO	320	t	f
9536	311	107	BASICO	318	t	f
9537	311	47	INTERMEDIARIO	320	t	f
9538	311	48	BASICO	318	t	f
9539	311	49	INTERMEDIARIO	320	t	f
9540	311	50	INTERMEDIARIO	320	t	f
9541	311	51	INTERMEDIARIO	320	t	f
9542	311	52	INTERMEDIARIO	320	t	f
9543	311	28	BASICO	318	t	f
9544	311	29	INTERMEDIARIO	320	t	f
9545	311	30	BASICO	318	t	f
9546	311	31	INTERMEDIARIO	320	t	f
9547	311	32	BASICO	318	t	f
9548	311	33	BASICO	318	t	f
9549	311	34	BASICO	318	t	f
9550	311	35	INTERMEDIARIO	320	t	f
9551	311	36	INTERMEDIARIO	320	t	f
9552	311	37	BASICO	318	t	f
9553	311	38	BASICO	318	t	f
9554	311	39	INTERMEDIARIO	320	t	f
9555	311	40	INTERMEDIARIO	320	t	f
9556	311	41	INTERMEDIARIO	320	t	f
9557	311	42	BASICO	318	t	f
9558	311	43	BASICO	318	t	f
9559	311	44	BASICO	318	t	f
9560	311	45	BASICO	318	t	f
9561	311	46	BASICO	318	t	f
9562	311	13	BASICO	318	t	f
9563	311	14	BASICO	318	t	f
9564	311	15	BASICO	318	t	f
9565	311	16	BASICO	318	t	f
9566	311	17	BASICO	318	t	f
9567	311	18	BASICO	318	t	f
9568	311	19	BASICO	318	t	f
9569	311	20	BASICO	318	t	f
9570	311	21	BASICO	318	t	f
9571	311	22	BASICO	318	t	f
9572	311	23	BASICO	318	t	f
9573	311	24	BASICO	318	t	f
9574	311	25	BASICO	318	t	f
9575	311	26	BASICO	318	t	f
9576	311	27	BASICO	318	t	f
9577	311	53	INTERMEDIARIO	320	t	f
9578	311	54	BASICO	318	t	f
9579	311	55	BASICO	318	t	f
9580	311	56	BASICO	318	t	f
9581	311	57	INTERMEDIARIO	320	t	f
9582	311	58	INTERMEDIARIO	320	t	f
9583	311	59	INTERMEDIARIO	320	t	f
9584	311	60	INTERMEDIARIO	320	t	f
9585	311	61	INTERMEDIARIO	320	t	f
9586	311	62	BASICO	318	t	f
9587	311	83	BASICO	318	t	f
9588	311	84	INTERMEDIARIO	320	t	f
9589	311	85	INTERMEDIARIO	320	t	f
9590	311	86	INTERMEDIARIO	320	t	f
9591	311	88	BASICO	318	t	f
9592	311	89	BASICO	318	t	f
9593	311	90	BASICO	318	t	f
9594	311	91	INTERMEDIARIO	320	t	f
9595	311	92	BASICO	318	t	f
9596	311	93	BASICO	318	t	f
9597	311	94	INTERMEDIARIO	320	t	f
9598	311	95	INTERMEDIARIO	320	t	f
9599	311	96	INTERMEDIARIO	320	t	f
9600	311	130	BASICO	318	t	f
9601	311	113	BASICO	318	t	f
9602	311	114	INTERMEDIARIO	320	t	f
9603	311	115	INTERMEDIARIO	320	t	f
9604	311	116	BASICO	318	t	f
9605	311	117	BASICO	318	t	f
9606	311	118	BASICO	318	t	f
9607	311	119	INTERMEDIARIO	320	t	f
9608	311	120	INTERMEDIARIO	320	t	f
9609	311	121	BASICO	318	t	f
9610	311	122	BASICO	318	t	f
9611	311	123	BASICO	318	t	f
9612	311	124	INTERMEDIARIO	320	t	f
9613	311	125	INTERMEDIARIO	320	t	f
9614	311	126	BASICO	318	t	f
9615	311	127	BASICO	318	t	f
9616	311	129	INTERMEDIARIO	320	t	f
9617	311	1	INTERMEDIARIO	320	t	f
9618	311	2	BASICO	318	t	f
9619	311	3	INTERMEDIARIO	320	t	f
9620	311	4	INTERMEDIARIO	320	t	f
9621	311	5	BASICO	318	t	f
9622	311	6	BASICO	318	t	f
9623	311	7	INTERMEDIARIO	320	t	f
9624	311	8	BASICO	318	t	f
9625	311	9	INTERMEDIARIO	320	t	f
9626	311	10	BASICO	318	t	f
9627	311	11	BASICO	318	t	f
9628	311	12	BASICO	318	t	f
9629	311	63	BASICO	318	t	f
9630	311	64	BASICO	318	t	f
9631	311	65	BASICO	318	t	f
9632	311	66	BASICO	318	t	f
9633	311	67	INTERMEDIARIO	320	t	f
9634	311	68	BASICO	318	t	f
9635	311	69	BASICO	318	t	f
9636	311	70	INTERMEDIARIO	320	t	f
9637	311	71	BASICO	318	t	f
9638	311	72	BASICO	318	t	f
9639	311	73	BASICO	318	t	f
9640	311	74	BASICO	318	t	f
9641	311	75	BASICO	318	t	f
9642	311	76	INTERMEDIARIO	320	t	f
9643	311	77	INTERMEDIARIO	320	t	f
9644	311	78	BASICO	318	t	f
9645	311	79	BASICO	318	t	f
9646	311	81	BASICO	318	t	f
9647	311	82	BASICO	318	t	f
9648	311	108	BASICO	318	t	f
9649	311	110	BASICO	318	t	f
9650	311	111	INTERMEDIARIO	320	t	f
9651	311	112	INTERMEDIARIO	320	t	f
9652	88	98	INTERMEDIARIO	320	t	f
9653	88	99	BASICO	318	t	f
9654	88	100	BASICO	318	t	f
9655	88	101	INTERMEDIARIO	320	t	f
9656	88	102	BASICO	318	t	f
9657	88	103	INTERMEDIARIO	320	t	f
9658	88	104	BASICO	318	t	f
9659	88	105	BASICO	318	t	f
9660	88	106	AVANCADO	321	t	f
9661	88	107	BASICO	318	t	f
9662	88	47	BASICO	318	t	f
9663	88	48	BASICO	318	t	f
9664	88	49	BASICO	318	t	f
9665	88	50	BASICO	318	t	f
9666	88	51	BASICO	318	t	f
9667	88	52	INTERMEDIARIO	320	t	f
9668	88	28	BASICO	318	t	f
9669	88	29	BASICO	318	t	f
9670	88	30	BASICO	318	t	f
9671	88	31	BASICO	318	t	f
9672	88	32	BASICO	318	t	f
9673	88	34	INTERMEDIARIO	320	t	f
9674	88	35	INTERMEDIARIO	320	t	f
9675	88	36	INTERMEDIARIO	320	t	f
9676	88	37	INTERMEDIARIO	320	t	f
9677	88	38	AVANCADO	321	t	f
9678	88	39	INTERMEDIARIO	320	t	f
9679	88	40	BASICO	318	t	f
9680	88	41	BASICO	318	t	f
9681	88	42	BASICO	318	t	f
9682	88	43	INTERMEDIARIO	320	t	f
9683	88	44	BASICO	318	t	f
9684	88	45	BASICO	318	t	f
9685	88	46	BASICO	318	t	f
9686	88	13	BASICO	318	t	f
9687	88	14	INTERMEDIARIO	320	t	f
9688	88	15	BASICO	318	t	f
9689	88	16	INTERMEDIARIO	320	t	f
9690	88	17	INTERMEDIARIO	320	t	f
9691	88	18	BASICO	318	t	f
9692	88	19	BASICO	318	t	f
9693	88	20	BASICO	318	t	f
9694	88	21	AVANCADO	321	t	f
9695	88	22	AVANCADO	321	t	f
9696	88	23	BASICO	318	t	f
9697	88	24	BASICO	318	t	f
9698	88	25	BASICO	318	t	f
9699	88	26	BASICO	318	t	f
9700	88	27	BASICO	318	t	f
9701	88	53	BASICO	318	t	f
9702	88	54	BASICO	318	t	f
9703	88	55	BASICO	318	t	f
9704	88	56	BASICO	318	t	f
9705	88	57	BASICO	318	t	f
9706	88	58	BASICO	318	t	f
9707	88	59	INTERMEDIARIO	320	t	f
9708	88	60	INTERMEDIARIO	320	t	f
9709	88	61	BASICO	318	t	f
9710	88	62	BASICO	318	t	f
9711	88	83	BASICO	318	t	f
9712	88	84	BASICO	318	t	f
9713	88	85	BASICO	318	t	f
9714	88	86	BASICO	318	t	f
9715	88	87	BASICO	318	t	f
9716	88	88	BASICO	318	t	f
9717	88	89	BASICO	318	t	f
9718	88	90	BASICO	318	t	f
9719	88	91	BASICO	318	t	f
9720	88	92	BASICO	318	t	f
9721	88	93	BASICO	318	t	f
9722	88	94	BASICO	318	t	f
9723	88	95	BASICO	318	t	f
9724	88	96	BASICO	318	t	f
9725	88	97	BASICO	318	t	f
9726	88	130	BASICO	318	t	f
9727	88	113	BASICO	318	t	f
9728	88	114	BASICO	318	t	f
9729	88	115	BASICO	318	t	f
9730	88	116	BASICO	318	t	f
9731	88	117	AVANCADO	321	t	f
9732	88	118	BASICO	318	t	f
9733	88	119	INTERMEDIARIO	320	t	f
9734	88	120	BASICO	318	t	f
9735	88	121	BASICO	318	t	f
9736	88	122	BASICO	318	t	f
9737	88	123	BASICO	318	t	f
9738	88	124	BASICO	318	t	f
9739	88	125	BASICO	318	t	f
9740	88	126	BASICO	318	t	f
9741	88	127	BASICO	318	t	f
9742	88	129	INTERMEDIARIO	320	t	f
9743	88	1	BASICO	318	t	f
9744	88	2	BASICO	318	t	f
9745	88	3	BASICO	318	t	f
9746	88	4	BASICO	318	t	f
9747	88	5	BASICO	318	t	f
9748	88	6	BASICO	318	t	f
9749	88	7	BASICO	318	t	f
9750	88	8	BASICO	318	t	f
9751	88	9	BASICO	318	t	f
9752	88	10	BASICO	318	t	f
9753	88	11	BASICO	318	t	f
9754	88	12	BASICO	318	t	f
9755	88	63	BASICO	318	t	f
9756	88	64	INTERMEDIARIO	320	t	f
9757	88	65	BASICO	318	t	f
9758	88	66	BASICO	318	t	f
9759	88	67	BASICO	318	t	f
9760	88	68	BASICO	318	t	f
9761	88	69	BASICO	318	t	f
9762	88	70	BASICO	318	t	f
9763	88	71	BASICO	318	t	f
9764	88	72	INTERMEDIARIO	320	t	f
9765	88	73	BASICO	318	t	f
9766	88	74	BASICO	318	t	f
9767	88	75	BASICO	318	t	f
9768	88	76	BASICO	318	t	f
9769	88	77	BASICO	318	t	f
9770	88	78	BASICO	318	t	f
9771	88	79	BASICO	318	t	f
9772	88	81	BASICO	318	t	f
9773	88	82	INTERMEDIARIO	320	t	f
9774	88	108	BASICO	318	t	f
9775	88	109	BASICO	318	t	f
9776	88	110	BASICO	318	t	f
9777	88	111	BASICO	318	t	f
9778	88	112	BASICO	318	t	f
9779	4	98	INTERMEDIARIO	320	t	f
9780	4	99	BASICO	318	t	f
9781	4	100	INTERMEDIARIO	320	t	f
9782	4	101	AVANCADO	321	t	f
9783	4	102	AVANCADO	321	t	f
9784	4	103	AVANCADO	321	t	f
9785	4	104	BASICO	318	t	f
9786	4	106	AVANCADO	321	t	f
9787	4	107	INTERMEDIARIO	320	t	f
9788	4	47	BASICO	318	t	f
9789	4	48	BASICO	318	t	f
9790	4	49	BASICO	318	t	f
9791	4	50	AVANCADO	321	t	f
9792	4	51	BASICO	318	t	f
9793	4	52	AVANCADO	321	t	f
9794	4	28	BASICO	318	t	f
9795	4	29	BASICO	318	t	f
9796	4	30	AVANCADO	321	t	f
9797	4	31	INTERMEDIARIO	320	t	f
9798	4	32	BASICO	318	t	f
9799	4	33	BASICO	318	t	f
9800	4	34	INTERMEDIARIO	320	t	f
9801	4	35	AVANCADO	321	t	f
9802	4	36	AVANCADO	321	t	f
9803	4	37	AVANCADO	321	t	f
9804	4	38	AVANCADO	321	t	f
9805	4	39	AVANCADO	321	t	f
9806	4	40	AVANCADO	321	t	f
9807	4	41	INTERMEDIARIO	320	t	f
9808	4	43	BASICO	318	t	f
9809	4	44	BASICO	318	t	f
9810	4	45	BASICO	318	t	f
9811	4	46	BASICO	318	t	f
9812	4	13	INTERMEDIARIO	320	t	f
9813	4	14	BASICO	318	t	f
9814	4	15	INTERMEDIARIO	320	t	f
9815	4	16	INTERMEDIARIO	320	t	f
9816	4	17	BASICO	318	t	f
9817	4	18	BASICO	318	t	f
9818	4	19	BASICO	318	t	f
9819	4	20	INTERMEDIARIO	320	t	f
9820	4	21	BASICO	318	t	f
9821	4	22	BASICO	318	t	f
9822	4	23	BASICO	318	t	f
9823	4	24	BASICO	318	t	f
9824	4	25	BASICO	318	t	f
9825	4	26	INTERMEDIARIO	320	t	f
9826	4	27	BASICO	318	t	f
9827	4	53	AVANCADO	321	t	f
9828	4	54	AVANCADO	321	t	f
9829	4	55	AVANCADO	321	t	f
9830	4	56	AVANCADO	321	t	f
9831	4	57	BASICO	318	t	f
9832	4	58	AVANCADO	321	t	f
9833	4	59	INTERMEDIARIO	320	t	f
9834	4	60	INTERMEDIARIO	320	t	f
9835	4	61	INTERMEDIARIO	320	t	f
9836	4	62	INTERMEDIARIO	320	t	f
9837	4	83	INTERMEDIARIO	320	t	f
9838	4	84	INTERMEDIARIO	320	t	f
9839	4	85	INTERMEDIARIO	320	t	f
9840	4	86	INTERMEDIARIO	320	t	f
9841	4	87	INTERMEDIARIO	320	t	f
9842	4	88	INTERMEDIARIO	320	t	f
9843	4	89	INTERMEDIARIO	320	t	f
9844	4	90	BASICO	318	t	f
9845	4	92	INTERMEDIARIO	320	t	f
9846	4	93	BASICO	318	t	f
9847	4	95	INTERMEDIARIO	320	t	f
9848	4	96	BASICO	318	t	f
9849	4	97	BASICO	318	t	f
9850	4	130	BASICO	318	t	f
9851	4	113	BASICO	318	t	f
9852	4	114	BASICO	318	t	f
9853	4	115	AVANCADO	321	t	f
9854	4	116	AVANCADO	321	t	f
9855	4	117	AVANCADO	321	t	f
9856	4	118	AVANCADO	321	t	f
9857	4	119	AVANCADO	321	t	f
9858	4	120	AVANCADO	321	t	f
9859	4	121	BASICO	318	t	f
9860	4	122	BASICO	318	t	f
9861	4	123	INTERMEDIARIO	320	t	f
9862	4	124	BASICO	318	t	f
9863	4	125	BASICO	318	t	f
9864	4	126	BASICO	318	t	f
9865	4	127	BASICO	318	t	f
9866	4	129	BASICO	318	t	f
9867	4	1	BASICO	318	t	f
9868	4	2	BASICO	318	t	f
9869	4	3	BASICO	318	t	f
9870	4	4	INTERMEDIARIO	320	t	f
9871	4	6	BASICO	318	t	f
9872	4	9	BASICO	318	t	f
9873	4	10	AVANCADO	321	t	f
9874	4	11	BASICO	318	t	f
9875	4	12	BASICO	318	t	f
9876	4	63	INTERMEDIARIO	320	t	f
9877	4	64	INTERMEDIARIO	320	t	f
9878	4	65	INTERMEDIARIO	320	t	f
9879	4	66	INTERMEDIARIO	320	t	f
9880	4	67	INTERMEDIARIO	320	t	f
9881	4	68	BASICO	318	t	f
9882	4	69	BASICO	318	t	f
9883	4	70	BASICO	318	t	f
9884	4	71	BASICO	318	t	f
9885	4	72	INTERMEDIARIO	320	t	f
9886	4	73	BASICO	318	t	f
9887	4	74	BASICO	318	t	f
9888	4	75	INTERMEDIARIO	320	t	f
9889	4	76	BASICO	318	t	f
9890	4	77	INTERMEDIARIO	320	t	f
9891	4	78	BASICO	318	t	f
9892	4	79	INTERMEDIARIO	320	t	f
9893	4	81	INTERMEDIARIO	320	t	f
9894	4	82	INTERMEDIARIO	320	t	f
9895	4	108	BASICO	318	t	f
9896	4	109	BASICO	318	t	f
9897	4	110	BASICO	318	t	f
9898	4	111	BASICO	318	t	f
9899	4	112	BASICO	318	t	f
9900	183	98	BASICO	318	t	f
9901	183	106	INTERMEDIARIO	320	t	f
9902	183	107	BASICO	318	t	f
9903	183	50	BASICO	318	t	f
9904	183	29	BASICO	318	t	f
9905	183	33	BASICO	318	t	f
9906	183	34	BASICO	318	t	f
9907	183	36	BASICO	318	t	f
9908	183	37	BASICO	318	t	f
9909	183	14	BASICO	318	t	f
9910	183	21	INTERMEDIARIO	320	t	f
9911	183	22	BASICO	318	t	f
9912	183	27	BASICO	318	t	f
9913	183	55	BASICO	318	t	f
9914	183	56	BASICO	318	t	f
9915	183	94	BASICO	318	t	f
9916	183	113	INTERMEDIARIO	320	t	f
9917	183	115	INTERMEDIARIO	320	t	f
9918	183	117	INTERMEDIARIO	320	t	f
9919	183	119	BASICO	318	t	f
9920	183	123	BASICO	318	t	f
9921	183	129	INTERMEDIARIO	320	t	f
9922	183	65	INTERMEDIARIO	320	t	f
9923	183	66	INTERMEDIARIO	320	t	f
9924	183	67	BASICO	318	t	f
9925	183	71	BASICO	318	t	f
9926	183	72	INTERMEDIARIO	320	t	f
9927	183	81	BASICO	318	t	f
9928	183	82	INTERMEDIARIO	320	t	f
9929	209	103	INTERMEDIARIO	320	t	f
9930	209	106	AVANCADO	321	t	f
9931	209	50	AVANCADO	321	t	f
9932	209	52	AVANCADO	321	t	f
9933	209	36	INTERMEDIARIO	320	t	f
9934	209	20	INTERMEDIARIO	320	t	f
9935	209	55	INTERMEDIARIO	320	t	f
9936	209	56	AVANCADO	321	t	f
9937	209	58	INTERMEDIARIO	320	t	f
9938	209	59	INTERMEDIARIO	320	t	f
9939	209	115	INTERMEDIARIO	320	t	f
9940	209	117	AVANCADO	321	t	f
9941	209	119	INTERMEDIARIO	320	t	f
9942	99	102	BASICO	318	t	f
9943	99	103	INTERMEDIARIO	320	t	f
9944	99	104	INTERMEDIARIO	320	t	f
9945	99	105	INTERMEDIARIO	320	t	f
9946	99	106	INTERMEDIARIO	320	t	f
9947	99	107	INTERMEDIARIO	320	t	f
9948	99	49	INTERMEDIARIO	320	t	f
9949	99	50	BASICO	318	t	f
9950	99	33	BASICO	318	t	f
9951	99	34	INTERMEDIARIO	320	t	f
9952	99	36	INTERMEDIARIO	320	t	f
9953	99	37	INTERMEDIARIO	320	t	f
9954	99	16	INTERMEDIARIO	320	t	f
9955	99	20	INTERMEDIARIO	320	t	f
9956	99	21	INTERMEDIARIO	320	t	f
9957	99	53	INTERMEDIARIO	320	t	f
9958	99	55	INTERMEDIARIO	320	t	f
9959	99	56	INTERMEDIARIO	320	t	f
9960	99	58	INTERMEDIARIO	320	t	f
9961	99	59	INTERMEDIARIO	320	t	f
9962	99	115	INTERMEDIARIO	320	t	f
9963	99	117	INTERMEDIARIO	320	t	f
9964	99	129	BASICO	318	t	f
9965	99	3	INTERMEDIARIO	320	t	f
9966	99	9	INTERMEDIARIO	320	t	f
9967	99	10	BASICO	318	t	f
9968	99	12	INTERMEDIARIO	320	t	f
9969	99	63	BASICO	318	t	f
9970	99	65	BASICO	318	t	f
9971	99	66	BASICO	318	t	f
9972	99	72	INTERMEDIARIO	320	t	f
9973	99	77	BASICO	318	t	f
9974	99	82	INTERMEDIARIO	320	t	f
9975	1	98	BASICO	318	t	f
9976	1	103	BASICO	318	t	f
9977	1	105	BASICO	318	t	f
9978	1	106	BASICO	318	t	f
9979	1	107	BASICO	318	t	f
9980	1	47	BASICO	318	t	f
9981	1	48	BASICO	318	t	f
9982	1	49	BASICO	318	t	f
9983	1	50	INTERMEDIARIO	320	t	f
9984	1	51	BASICO	318	t	f
9985	1	52	INTERMEDIARIO	320	t	f
9986	1	29	BASICO	318	t	f
9987	1	31	INTERMEDIARIO	320	t	f
9988	1	33	INTERMEDIARIO	320	t	f
9989	1	34	BASICO	318	t	f
9990	1	36	INTERMEDIARIO	320	t	f
9991	1	38	BASICO	318	t	f
9992	1	39	BASICO	318	t	f
9993	1	40	INTERMEDIARIO	320	t	f
9994	1	41	INTERMEDIARIO	320	t	f
9995	1	43	INTERMEDIARIO	320	t	f
9996	1	44	INTERMEDIARIO	320	t	f
9997	1	14	INTERMEDIARIO	320	t	f
9998	1	15	BASICO	318	t	f
9999	1	16	BASICO	318	t	f
10000	1	18	INTERMEDIARIO	320	t	f
10001	1	19	INTERMEDIARIO	320	t	f
10002	1	20	INTERMEDIARIO	320	t	f
10003	1	21	INTERMEDIARIO	320	t	f
10004	1	22	BASICO	318	t	f
10005	1	26	BASICO	318	t	f
10006	1	27	BASICO	318	t	f
10007	1	53	BASICO	318	t	f
10008	1	54	BASICO	318	t	f
10009	1	55	INTERMEDIARIO	320	t	f
10010	1	56	INTERMEDIARIO	320	t	f
10011	1	57	BASICO	318	t	f
10012	1	58	INTERMEDIARIO	320	t	f
10013	1	59	INTERMEDIARIO	320	t	f
10014	1	60	INTERMEDIARIO	320	t	f
10015	1	61	INTERMEDIARIO	320	t	f
10016	1	62	BASICO	318	t	f
10017	1	84	BASICO	318	t	f
10018	1	92	BASICO	318	t	f
10019	1	94	BASICO	318	t	f
10020	1	96	BASICO	318	t	f
10021	1	113	INTERMEDIARIO	320	t	f
10022	1	114	INTERMEDIARIO	320	t	f
10023	1	115	INTERMEDIARIO	320	t	f
10024	1	116	INTERMEDIARIO	320	t	f
10025	1	117	INTERMEDIARIO	320	t	f
10026	1	118	INTERMEDIARIO	320	t	f
10027	1	119	INTERMEDIARIO	320	t	f
10028	1	120	BASICO	318	t	f
10029	1	123	BASICO	318	t	f
10030	1	124	BASICO	318	t	f
10031	1	129	INTERMEDIARIO	320	t	f
10032	1	1	INTERMEDIARIO	320	t	f
10033	1	4	INTERMEDIARIO	320	t	f
10034	1	5	BASICO	318	t	f
10035	1	7	BASICO	318	t	f
10036	1	8	BASICO	318	t	f
10037	1	10	BASICO	318	t	f
10038	1	12	BASICO	318	t	f
10039	1	63	BASICO	318	t	f
10040	1	64	BASICO	318	t	f
10041	1	65	INTERMEDIARIO	320	t	f
10042	1	66	INTERMEDIARIO	320	t	f
10043	1	67	BASICO	318	t	f
10044	1	69	BASICO	318	t	f
10045	1	71	BASICO	318	t	f
10046	1	72	INTERMEDIARIO	320	t	f
10047	1	75	BASICO	318	t	f
10048	1	82	BASICO	318	t	f
10049	1	108	BASICO	318	t	f
10050	1	109	INTERMEDIARIO	320	t	f
10051	1	110	BASICO	318	t	f
10052	94	99	INTERMEDIARIO	320	t	f
10053	94	100	BASICO	318	t	f
10054	94	101	BASICO	318	t	f
10055	94	102	INTERMEDIARIO	320	t	f
10056	94	103	INTERMEDIARIO	320	t	f
10057	94	104	INTERMEDIARIO	320	t	f
10058	94	105	AVANCADO	321	t	f
10059	94	106	INTERMEDIARIO	320	t	f
10060	94	107	INTERMEDIARIO	320	t	f
10061	94	48	BASICO	318	t	f
10062	94	49	BASICO	318	t	f
10063	94	50	BASICO	318	t	f
10064	94	51	INTERMEDIARIO	320	t	f
10065	94	52	BASICO	318	t	f
10066	94	28	BASICO	318	t	f
10067	94	29	INTERMEDIARIO	320	t	f
10068	94	30	BASICO	318	t	f
10069	94	33	BASICO	318	t	f
10070	94	34	BASICO	318	t	f
10071	94	35	AVANCADO	321	t	f
10072	94	36	AVANCADO	321	t	f
10073	94	37	INTERMEDIARIO	320	t	f
10074	94	38	AVANCADO	321	t	f
10075	94	39	INTERMEDIARIO	320	t	f
10076	94	41	INTERMEDIARIO	320	t	f
10077	94	42	BASICO	318	t	f
10078	94	43	INTERMEDIARIO	320	t	f
10079	94	44	INTERMEDIARIO	320	t	f
10080	94	16	BASICO	318	t	f
10081	94	18	INTERMEDIARIO	320	t	f
10082	94	19	BASICO	318	t	f
10083	94	20	INTERMEDIARIO	320	t	f
10084	94	21	BASICO	318	t	f
10085	94	26	BASICO	318	t	f
10086	94	53	BASICO	318	t	f
10087	94	54	BASICO	318	t	f
10088	94	55	INTERMEDIARIO	320	t	f
10089	94	56	AVANCADO	321	t	f
10090	94	58	INTERMEDIARIO	320	t	f
10091	94	59	BASICO	318	t	f
10092	94	84	BASICO	318	t	f
10093	94	94	BASICO	318	t	f
10094	94	1	BASICO	318	t	f
10095	94	6	BASICO	318	t	f
10096	94	9	BASICO	318	t	f
10097	94	12	INTERMEDIARIO	320	t	f
10098	94	64	BASICO	318	t	f
10099	94	111	BASICO	318	t	f
10100	288	98	BASICO	318	t	f
10101	288	99	BASICO	318	t	f
10102	288	100	BASICO	318	t	f
10103	288	101	BASICO	318	t	f
10104	288	102	INTERMEDIARIO	320	t	f
10105	288	103	BASICO	318	t	f
10106	288	104	BASICO	318	t	f
10107	288	105	BASICO	318	t	f
10108	288	106	INTERMEDIARIO	320	t	f
10109	288	107	INTERMEDIARIO	320	t	f
10110	288	49	BASICO	318	t	f
10111	288	50	BASICO	318	t	f
10112	288	29	BASICO	318	t	f
10113	288	33	BASICO	318	t	f
10114	288	34	BASICO	318	t	f
10115	288	36	BASICO	318	t	f
10116	288	37	BASICO	318	t	f
10117	288	40	BASICO	318	t	f
10118	288	41	BASICO	318	t	f
10119	288	43	BASICO	318	t	f
10120	288	44	BASICO	318	t	f
10121	288	14	BASICO	318	t	f
10122	288	15	BASICO	318	t	f
10123	288	16	BASICO	318	t	f
10124	288	19	BASICO	318	t	f
10125	288	20	BASICO	318	t	f
10126	288	21	BASICO	318	t	f
10127	288	27	BASICO	318	t	f
10128	288	54	BASICO	318	t	f
10129	288	55	BASICO	318	t	f
10130	288	56	BASICO	318	t	f
10131	288	58	BASICO	318	t	f
10132	288	60	BASICO	318	t	f
10133	288	61	BASICO	318	t	f
10134	288	84	BASICO	318	t	f
10135	288	92	BASICO	318	t	f
10136	288	93	BASICO	318	t	f
10137	288	94	BASICO	318	t	f
10138	288	113	BASICO	318	t	f
10139	288	114	BASICO	318	t	f
10140	288	115	BASICO	318	t	f
10141	288	117	BASICO	318	t	f
10142	288	119	BASICO	318	t	f
10143	288	129	BASICO	318	t	f
10144	288	1	BASICO	318	t	f
10145	288	2	BASICO	318	t	f
10146	288	12	BASICO	318	t	f
10147	288	63	BASICO	318	t	f
10148	288	64	BASICO	318	t	f
10149	288	65	BASICO	318	t	f
10150	288	66	BASICO	318	t	f
10151	288	72	BASICO	318	t	f
10152	288	74	BASICO	318	t	f
10153	288	75	BASICO	318	t	f
10154	288	82	BASICO	318	t	f
10155	288	111	BASICO	318	t	f
10156	177	102	BASICO	318	t	f
10157	177	104	BASICO	318	t	f
10158	177	105	BASICO	318	t	f
10159	177	106	INTERMEDIARIO	320	t	f
10160	177	49	BASICO	318	t	f
10161	177	50	INTERMEDIARIO	320	t	f
10162	177	36	BASICO	318	t	f
10163	177	40	BASICO	318	t	f
10164	177	55	INTERMEDIARIO	320	t	f
10165	177	56	INTERMEDIARIO	320	t	f
10166	177	58	INTERMEDIARIO	320	t	f
10167	177	115	BASICO	318	t	f
10168	177	9	INTERMEDIARIO	320	t	f
10169	177	12	INTERMEDIARIO	320	t	f
10170	46	29	BASICO	318	t	f
10171	46	35	BASICO	318	t	f
10172	46	36	BASICO	318	t	f
10173	46	39	BASICO	318	t	f
10174	46	2	BASICO	318	t	f
10175	46	72	BASICO	318	t	f
10176	46	82	BASICO	318	t	f
10177	35	98	BASICO	318	t	f
10178	35	99	BASICO	318	t	f
10179	35	100	BASICO	318	t	f
10180	35	101	BASICO	318	t	f
10181	35	102	BASICO	318	t	f
10182	35	103	BASICO	318	t	f
10183	35	104	BASICO	318	t	f
10184	35	106	INTERMEDIARIO	320	t	f
10185	35	107	INTERMEDIARIO	320	t	f
10186	35	47	BASICO	318	t	f
10187	35	48	BASICO	318	t	f
10188	35	49	BASICO	318	t	f
10189	35	50	BASICO	318	t	f
10190	35	51	BASICO	318	t	f
10191	35	52	BASICO	318	t	f
10192	35	28	INTERMEDIARIO	320	t	f
10193	35	29	INTERMEDIARIO	320	t	f
10194	35	30	INTERMEDIARIO	320	t	f
10195	35	31	BASICO	318	t	f
10196	35	32	BASICO	318	t	f
10197	35	33	BASICO	318	t	f
10198	35	34	BASICO	318	t	f
10199	35	35	AVANCADO	321	t	f
10200	35	36	AVANCADO	321	t	f
10201	35	37	AVANCADO	321	t	f
10202	35	38	AVANCADO	321	t	f
10203	35	39	AVANCADO	321	t	f
10204	35	40	INTERMEDIARIO	320	t	f
10205	35	41	INTERMEDIARIO	320	t	f
10206	35	42	BASICO	318	t	f
10207	35	43	BASICO	318	t	f
10208	35	44	INTERMEDIARIO	320	t	f
10209	35	45	BASICO	318	t	f
10210	35	46	BASICO	318	t	f
10211	35	16	BASICO	318	t	f
10212	35	17	BASICO	318	t	f
10213	35	19	BASICO	318	t	f
10214	35	20	BASICO	318	t	f
10215	35	26	BASICO	318	t	f
10216	35	53	BASICO	318	t	f
10217	35	54	BASICO	318	t	f
10218	35	55	BASICO	318	t	f
10219	35	56	BASICO	318	t	f
10220	35	58	BASICO	318	t	f
10221	35	59	BASICO	318	t	f
10222	35	60	BASICO	318	t	f
10223	35	61	BASICO	318	t	f
10224	35	89	BASICO	318	t	f
10225	35	90	BASICO	318	t	f
10226	35	94	BASICO	318	t	f
10227	35	115	BASICO	318	t	f
10228	35	117	BASICO	318	t	f
10229	35	119	BASICO	318	t	f
10230	35	122	BASICO	318	t	f
10231	35	129	BASICO	318	t	f
10232	35	1	AVANCADO	321	t	f
10233	35	2	INTERMEDIARIO	320	t	f
10234	35	3	BASICO	318	t	f
10235	35	4	BASICO	318	t	f
10236	35	5	BASICO	318	t	f
10237	35	7	BASICO	318	t	f
10238	35	8	BASICO	318	t	f
10239	35	9	INTERMEDIARIO	320	t	f
10240	35	10	BASICO	318	t	f
10241	35	11	BASICO	318	t	f
10242	35	12	INTERMEDIARIO	320	t	f
10243	35	65	BASICO	318	t	f
10244	35	82	BASICO	318	t	f
10245	35	108	BASICO	318	t	f
10246	35	109	INTERMEDIARIO	320	t	f
10247	35	110	BASICO	318	t	f
10248	35	111	BASICO	318	t	f
10249	35	112	BASICO	318	t	f
10250	152	14	BASICO	318	t	f
10251	152	16	BASICO	318	t	f
10252	152	21	BASICO	318	t	f
10253	152	56	BASICO	318	t	f
10254	152	58	BASICO	318	t	f
10255	152	62	BASICO	318	t	f
10256	152	64	BASICO	318	t	f
10257	152	72	BASICO	318	t	f
10258	152	108	BASICO	318	t	f
10259	152	109	BASICO	318	t	f
10260	152	110	BASICO	318	t	f
10261	152	111	BASICO	318	t	f
10262	152	112	BASICO	318	t	f
10263	27	105	INTERMEDIARIO	320	t	f
10264	27	50	INTERMEDIARIO	320	t	f
10265	27	35	INTERMEDIARIO	320	t	f
10266	27	40	INTERMEDIARIO	320	t	f
10267	27	41	INTERMEDIARIO	320	t	f
10268	27	21	INTERMEDIARIO	320	t	f
10269	96	98	INTERMEDIARIO	320	t	f
10270	96	100	INTERMEDIARIO	320	t	f
10271	96	103	INTERMEDIARIO	320	t	f
10272	96	104	INTERMEDIARIO	320	t	f
10273	96	105	INTERMEDIARIO	320	t	f
10274	96	106	INTERMEDIARIO	320	t	f
10275	96	107	AVANCADO	321	t	f
10276	96	48	INTERMEDIARIO	320	t	f
10277	96	49	INTERMEDIARIO	320	t	f
10278	96	50	INTERMEDIARIO	320	t	f
10279	96	51	INTERMEDIARIO	320	t	f
10280	96	52	BASICO	318	t	f
10281	96	28	BASICO	318	t	f
10282	96	29	BASICO	318	t	f
10283	96	30	BASICO	318	t	f
10284	96	31	BASICO	318	t	f
10285	96	32	BASICO	318	t	f
10286	96	33	BASICO	318	t	f
10287	96	34	BASICO	318	t	f
10288	96	35	BASICO	318	t	f
10289	96	36	INTERMEDIARIO	320	t	f
10290	96	37	INTERMEDIARIO	320	t	f
10291	96	38	BASICO	318	t	f
10292	96	39	BASICO	318	t	f
10293	96	40	INTERMEDIARIO	320	t	f
10294	96	41	INTERMEDIARIO	320	t	f
10295	96	42	BASICO	318	t	f
10296	96	43	BASICO	318	t	f
10297	96	44	BASICO	318	t	f
10298	96	45	BASICO	318	t	f
10299	96	46	BASICO	318	t	f
10300	96	13	BASICO	318	t	f
10301	96	14	BASICO	318	t	f
10302	96	15	BASICO	318	t	f
10303	96	16	INTERMEDIARIO	320	t	f
10304	96	17	BASICO	318	t	f
10305	96	18	BASICO	318	t	f
10306	96	19	BASICO	318	t	f
10307	96	20	BASICO	318	t	f
10308	96	21	BASICO	318	t	f
10309	96	22	BASICO	318	t	f
10310	96	23	BASICO	318	t	f
10311	96	24	BASICO	318	t	f
10312	96	25	BASICO	318	t	f
10313	96	26	BASICO	318	t	f
10314	96	27	BASICO	318	t	f
10315	96	53	BASICO	318	t	f
10316	96	54	BASICO	318	t	f
10317	96	55	BASICO	318	t	f
10318	96	56	BASICO	318	t	f
10319	96	57	BASICO	318	t	f
10320	96	58	BASICO	318	t	f
10321	96	59	BASICO	318	t	f
10322	96	60	BASICO	318	t	f
10323	96	61	BASICO	318	t	f
10324	96	62	BASICO	318	t	f
10325	96	83	BASICO	318	t	f
10326	96	84	BASICO	318	t	f
10327	96	85	BASICO	318	t	f
10328	96	86	BASICO	318	t	f
10329	96	87	BASICO	318	t	f
10330	96	88	BASICO	318	t	f
10331	96	89	BASICO	318	t	f
10332	96	90	BASICO	318	t	f
10333	96	91	BASICO	318	t	f
10334	96	92	BASICO	318	t	f
10335	96	93	BASICO	318	t	f
10336	96	94	INTERMEDIARIO	320	t	f
10337	96	95	BASICO	318	t	f
10338	96	96	INTERMEDIARIO	320	t	f
10339	96	97	BASICO	318	t	f
10340	96	130	BASICO	318	t	f
10341	96	113	BASICO	318	t	f
10342	96	114	BASICO	318	t	f
10343	96	115	BASICO	318	t	f
10344	96	116	BASICO	318	t	f
10345	96	117	INTERMEDIARIO	320	t	f
10346	96	118	BASICO	318	t	f
10347	96	119	BASICO	318	t	f
10348	96	120	BASICO	318	t	f
10349	96	121	BASICO	318	t	f
10350	96	122	BASICO	318	t	f
10351	96	123	BASICO	318	t	f
10352	96	124	BASICO	318	t	f
10353	96	125	BASICO	318	t	f
10354	96	126	BASICO	318	t	f
10355	96	127	BASICO	318	t	f
10356	96	129	BASICO	318	t	f
10357	96	1	BASICO	318	t	f
10358	96	3	INTERMEDIARIO	320	t	f
10359	96	4	BASICO	318	t	f
10360	96	5	INTERMEDIARIO	320	t	f
10361	96	6	BASICO	318	t	f
10362	96	7	BASICO	318	t	f
10363	96	8	BASICO	318	t	f
10364	96	9	INTERMEDIARIO	320	t	f
10365	96	10	BASICO	318	t	f
10366	96	11	BASICO	318	t	f
10367	96	63	BASICO	318	t	f
10368	96	64	BASICO	318	t	f
10369	96	65	BASICO	318	t	f
10370	96	66	BASICO	318	t	f
10371	96	67	BASICO	318	t	f
10372	96	68	BASICO	318	t	f
10373	96	69	BASICO	318	t	f
10374	96	70	BASICO	318	t	f
10375	96	71	BASICO	318	t	f
10376	96	72	BASICO	318	t	f
10377	96	73	BASICO	318	t	f
10378	96	74	BASICO	318	t	f
10379	96	75	BASICO	318	t	f
10380	96	76	BASICO	318	t	f
10381	96	77	BASICO	318	t	f
10382	96	78	BASICO	318	t	f
10383	96	79	BASICO	318	t	f
10384	96	81	BASICO	318	t	f
10385	96	82	BASICO	318	t	f
10386	96	108	BASICO	318	t	f
10387	96	109	BASICO	318	t	f
10388	96	110	BASICO	318	t	f
10389	96	111	BASICO	318	t	f
10390	96	112	BASICO	318	t	f
10391	188	98	INTERMEDIARIO	320	t	f
10392	188	102	INTERMEDIARIO	320	t	f
10393	188	103	AVANCADO	321	t	f
10394	188	106	AVANCADO	321	t	f
10395	188	47	INTERMEDIARIO	320	t	f
10396	188	48	BASICO	318	t	f
10397	188	49	AVANCADO	321	t	f
10398	188	50	AVANCADO	321	t	f
10399	188	51	AVANCADO	321	t	f
10400	188	52	INTERMEDIARIO	320	t	f
10401	188	30	BASICO	318	t	f
10402	188	35	BASICO	318	t	f
10403	188	36	BASICO	318	t	f
10404	188	40	BASICO	318	t	f
10405	188	41	BASICO	318	t	f
10406	188	21	BASICO	318	t	f
10407	188	55	BASICO	318	t	f
10408	188	56	BASICO	318	t	f
10409	188	59	BASICO	318	t	f
10410	188	60	BASICO	318	t	f
10411	188	61	BASICO	318	t	f
10412	188	115	BASICO	318	t	f
10413	188	117	BASICO	318	t	f
10414	188	119	BASICO	318	t	f
10415	188	2	BASICO	318	t	f
10416	188	7	BASICO	318	t	f
10417	188	8	BASICO	318	t	f
10418	188	9	BASICO	318	t	f
10419	188	10	BASICO	318	t	f
10420	188	12	BASICO	318	t	f
10421	188	64	INTERMEDIARIO	320	t	f
10422	188	72	BASICO	318	t	f
10423	188	82	BASICO	318	t	f
10424	198	98	INTERMEDIARIO	320	t	f
10425	198	99	BASICO	318	t	f
10426	198	100	INTERMEDIARIO	320	t	f
10427	198	101	BASICO	318	t	f
10428	198	102	BASICO	318	t	f
10429	198	103	BASICO	318	t	f
10430	198	104	BASICO	318	t	f
10431	198	105	BASICO	318	t	f
10432	198	106	BASICO	318	t	f
10433	198	107	AVANCADO	321	t	f
10434	198	47	BASICO	318	t	f
10435	198	48	BASICO	318	t	f
10436	198	49	BASICO	318	t	f
10437	198	50	INTERMEDIARIO	320	t	f
10438	198	51	BASICO	318	t	f
10439	198	52	BASICO	318	t	f
10440	198	28	BASICO	318	t	f
10441	198	29	AVANCADO	321	t	f
10442	198	30	BASICO	318	t	f
10443	198	31	BASICO	318	t	f
10444	198	32	BASICO	318	t	f
10445	198	33	AVANCADO	321	t	f
10446	198	34	AVANCADO	321	t	f
10447	198	35	AVANCADO	321	t	f
10448	198	36	AVANCADO	321	t	f
10449	198	37	AVANCADO	321	t	f
10450	198	38	BASICO	318	t	f
10451	198	39	AVANCADO	321	t	f
10452	198	40	AVANCADO	321	t	f
10453	198	41	AVANCADO	321	t	f
10454	198	42	INTERMEDIARIO	320	t	f
10455	198	43	AVANCADO	321	t	f
10456	198	44	AVANCADO	321	t	f
10457	198	45	AVANCADO	321	t	f
10458	198	46	AVANCADO	321	t	f
10459	198	13	BASICO	318	t	f
10460	198	14	AVANCADO	321	t	f
10461	198	15	BASICO	318	t	f
10462	198	16	BASICO	318	t	f
10463	198	17	INTERMEDIARIO	320	t	f
10464	198	18	INTERMEDIARIO	320	t	f
10465	198	19	BASICO	318	t	f
10466	198	20	INTERMEDIARIO	320	t	f
10467	198	21	AVANCADO	321	t	f
10468	198	22	INTERMEDIARIO	320	t	f
10469	198	23	BASICO	318	t	f
10470	198	24	BASICO	318	t	f
10471	198	25	BASICO	318	t	f
10472	198	26	BASICO	318	t	f
10473	198	27	BASICO	318	t	f
10474	198	53	BASICO	318	t	f
10475	198	54	BASICO	318	t	f
10476	198	55	INTERMEDIARIO	320	t	f
10477	198	56	AVANCADO	321	t	f
10478	198	57	BASICO	318	t	f
10479	198	58	INTERMEDIARIO	320	t	f
10480	198	59	BASICO	318	t	f
10481	198	60	BASICO	318	t	f
10482	198	61	BASICO	318	t	f
10483	198	62	BASICO	318	t	f
10484	198	83	BASICO	318	t	f
10485	198	84	BASICO	318	t	f
10486	198	85	BASICO	318	t	f
10487	198	86	BASICO	318	t	f
10488	198	87	BASICO	318	t	f
10489	198	88	BASICO	318	t	f
10490	198	89	BASICO	318	t	f
10491	198	90	BASICO	318	t	f
10492	198	91	BASICO	318	t	f
10493	198	92	BASICO	318	t	f
10494	198	93	BASICO	318	t	f
10495	198	94	BASICO	318	t	f
10496	198	95	BASICO	318	t	f
10497	198	96	BASICO	318	t	f
10498	198	97	BASICO	318	t	f
10499	198	130	BASICO	318	t	f
10500	198	113	INTERMEDIARIO	320	t	f
10501	198	114	INTERMEDIARIO	320	t	f
10502	198	115	INTERMEDIARIO	320	t	f
10503	198	116	BASICO	318	t	f
10504	198	117	INTERMEDIARIO	320	t	f
10505	198	118	INTERMEDIARIO	320	t	f
10506	198	119	INTERMEDIARIO	320	t	f
10507	198	120	BASICO	318	t	f
10508	198	121	BASICO	318	t	f
10509	198	122	INTERMEDIARIO	320	t	f
10510	198	123	BASICO	318	t	f
10511	198	124	BASICO	318	t	f
10512	198	125	BASICO	318	t	f
10513	198	126	BASICO	318	t	f
10514	198	127	BASICO	318	t	f
10515	198	129	INTERMEDIARIO	320	t	f
10516	198	1	AVANCADO	321	t	f
10517	198	2	INTERMEDIARIO	320	t	f
10518	198	3	AVANCADO	321	t	f
10519	198	4	BASICO	318	t	f
10520	198	5	BASICO	318	t	f
10521	198	6	BASICO	318	t	f
10522	198	7	BASICO	318	t	f
10523	198	8	BASICO	318	t	f
10524	198	9	INTERMEDIARIO	320	t	f
10525	198	10	AVANCADO	321	t	f
10526	198	11	BASICO	318	t	f
10527	198	12	AVANCADO	321	t	f
10528	198	63	AVANCADO	321	t	f
10529	198	64	AVANCADO	321	t	f
10530	198	65	INTERMEDIARIO	320	t	f
10531	198	66	INTERMEDIARIO	320	t	f
10532	198	67	INTERMEDIARIO	320	t	f
10533	198	68	AVANCADO	321	t	f
10534	198	69	BASICO	318	t	f
10535	198	70	BASICO	318	t	f
10536	198	71	INTERMEDIARIO	320	t	f
10537	198	72	INTERMEDIARIO	320	t	f
10538	198	73	BASICO	318	t	f
10539	198	74	AVANCADO	321	t	f
10540	198	75	BASICO	318	t	f
10541	198	76	BASICO	318	t	f
10542	198	77	BASICO	318	t	f
10543	198	78	BASICO	318	t	f
10544	198	79	AVANCADO	321	t	f
10545	198	81	BASICO	318	t	f
10546	198	82	AVANCADO	321	t	f
10547	198	108	INTERMEDIARIO	320	t	f
10548	198	109	BASICO	318	t	f
10549	198	110	BASICO	318	t	f
10550	198	111	BASICO	318	t	f
10551	198	112	BASICO	318	t	f
10552	83	104	BASICO	318	t	f
10553	83	106	INTERMEDIARIO	320	t	f
10554	83	50	BASICO	318	t	f
10555	83	51	BASICO	318	t	f
10556	83	52	INTERMEDIARIO	320	t	f
10557	83	29	BASICO	318	t	f
10558	83	41	BASICO	318	t	f
10559	83	44	BASICO	318	t	f
10560	83	14	INTERMEDIARIO	320	t	f
10561	83	15	BASICO	318	t	f
10562	83	16	BASICO	318	t	f
10563	83	18	BASICO	318	t	f
10564	83	19	INTERMEDIARIO	320	t	f
10565	83	20	BASICO	318	t	f
10566	83	26	BASICO	318	t	f
10567	83	53	BASICO	318	t	f
10568	83	54	BASICO	318	t	f
10569	83	55	INTERMEDIARIO	320	t	f
10570	83	56	INTERMEDIARIO	320	t	f
10571	83	57	BASICO	318	t	f
10572	83	58	INTERMEDIARIO	320	t	f
10573	83	59	INTERMEDIARIO	320	t	f
10574	83	60	BASICO	318	t	f
10575	83	61	BASICO	318	t	f
10576	83	62	AVANCADO	321	t	f
10577	83	89	BASICO	318	t	f
10578	83	117	INTERMEDIARIO	320	t	f
10579	83	118	INTERMEDIARIO	320	t	f
10580	83	129	BASICO	318	t	f
10581	83	1	BASICO	318	t	f
10582	83	2	BASICO	318	t	f
10583	83	8	BASICO	318	t	f
10584	83	63	BASICO	318	t	f
10585	83	65	BASICO	318	t	f
10586	83	72	INTERMEDIARIO	320	t	f
10587	83	82	BASICO	318	t	f
10588	83	108	BASICO	318	t	f
10589	83	109	INTERMEDIARIO	320	t	f
10590	83	110	BASICO	318	t	f
10591	224	98	BASICO	318	t	f
10592	224	99	BASICO	318	t	f
10593	224	100	BASICO	318	t	f
10594	224	102	INTERMEDIARIO	320	t	f
10595	224	103	BASICO	318	t	f
10596	224	104	BASICO	318	t	f
10597	224	105	AVANCADO	321	t	f
10598	224	106	AVANCADO	321	t	f
10599	224	107	BASICO	318	t	f
10600	224	50	INTERMEDIARIO	320	t	f
10601	224	52	INTERMEDIARIO	320	t	f
10602	224	29	AVANCADO	321	t	f
10603	224	30	BASICO	318	t	f
10604	224	34	BASICO	318	t	f
10605	224	35	INTERMEDIARIO	320	t	f
10606	224	36	INTERMEDIARIO	320	t	f
10607	224	38	INTERMEDIARIO	320	t	f
10608	224	40	AVANCADO	321	t	f
10609	224	41	AVANCADO	321	t	f
10610	224	43	AVANCADO	321	t	f
10611	224	44	BASICO	318	t	f
10612	224	13	BASICO	318	t	f
10613	224	14	AVANCADO	321	t	f
10614	224	15	BASICO	318	t	f
10615	224	16	INTERMEDIARIO	320	t	f
10616	224	19	INTERMEDIARIO	320	t	f
10617	224	20	INTERMEDIARIO	320	t	f
10618	224	21	AVANCADO	321	t	f
10619	224	25	BASICO	318	t	f
10620	224	26	BASICO	318	t	f
10621	224	53	BASICO	318	t	f
10622	224	54	BASICO	318	t	f
10623	224	55	INTERMEDIARIO	320	t	f
10624	224	56	INTERMEDIARIO	320	t	f
10625	224	58	INTERMEDIARIO	320	t	f
10626	224	59	INTERMEDIARIO	320	t	f
10627	224	61	INTERMEDIARIO	320	t	f
10628	224	62	AVANCADO	321	t	f
10629	224	89	BASICO	318	t	f
10630	224	92	BASICO	318	t	f
10631	224	94	BASICO	318	t	f
10632	224	96	BASICO	318	t	f
10633	224	97	BASICO	318	t	f
10634	224	113	BASICO	318	t	f
10635	224	114	BASICO	318	t	f
10636	224	115	AVANCADO	321	t	f
10637	224	116	BASICO	318	t	f
10638	224	117	AVANCADO	321	t	f
10639	224	119	AVANCADO	321	t	f
10640	224	120	INTERMEDIARIO	320	t	f
10641	224	123	BASICO	318	t	f
10642	224	124	BASICO	318	t	f
10643	224	129	INTERMEDIARIO	320	t	f
10644	224	1	INTERMEDIARIO	320	t	f
10645	224	2	INTERMEDIARIO	320	t	f
10646	224	8	INTERMEDIARIO	320	t	f
10647	224	9	INTERMEDIARIO	320	t	f
10648	224	10	INTERMEDIARIO	320	t	f
10649	224	63	BASICO	318	t	f
10650	224	64	BASICO	318	t	f
10651	224	65	INTERMEDIARIO	320	t	f
10652	224	66	INTERMEDIARIO	320	t	f
10653	224	71	BASICO	318	t	f
10654	224	72	AVANCADO	321	t	f
10655	224	75	BASICO	318	t	f
10656	224	82	INTERMEDIARIO	320	t	f
10657	224	109	BASICO	318	t	f
10658	224	110	BASICO	318	t	f
10659	135	100	INTERMEDIARIO	320	t	f
10660	135	106	INTERMEDIARIO	320	t	f
10661	135	107	INTERMEDIARIO	320	t	f
10662	135	49	INTERMEDIARIO	320	t	f
10663	135	50	INTERMEDIARIO	320	t	f
10664	135	52	INTERMEDIARIO	320	t	f
10665	135	29	INTERMEDIARIO	320	t	f
10666	135	36	INTERMEDIARIO	320	t	f
10667	135	40	INTERMEDIARIO	320	t	f
10668	135	41	INTERMEDIARIO	320	t	f
10669	135	43	INTERMEDIARIO	320	t	f
10670	135	14	INTERMEDIARIO	320	t	f
10671	135	19	INTERMEDIARIO	320	t	f
10672	135	21	INTERMEDIARIO	320	t	f
10673	135	26	INTERMEDIARIO	320	t	f
10674	135	53	INTERMEDIARIO	320	t	f
10675	135	54	INTERMEDIARIO	320	t	f
10676	135	55	AVANCADO	321	t	f
10677	135	56	AVANCADO	321	t	f
10678	135	58	AVANCADO	321	t	f
10679	135	62	AVANCADO	321	t	f
10680	135	97	BASICO	318	t	f
10681	135	115	AVANCADO	321	t	f
10682	135	116	AVANCADO	321	t	f
10683	135	117	AVANCADO	321	t	f
10684	135	119	AVANCADO	321	t	f
10685	135	129	BASICO	318	t	f
10686	135	1	INTERMEDIARIO	320	t	f
10687	135	2	INTERMEDIARIO	320	t	f
10688	135	12	INTERMEDIARIO	320	t	f
10689	135	65	BASICO	318	t	f
10690	135	66	BASICO	318	t	f
10691	135	72	INTERMEDIARIO	320	t	f
10692	135	108	BASICO	318	t	f
10693	135	110	BASICO	318	t	f
10694	93	98	BASICO	318	t	f
10695	93	104	BASICO	318	t	f
10696	93	106	INTERMEDIARIO	320	t	f
10697	93	50	INTERMEDIARIO	320	t	f
10698	93	51	BASICO	318	t	f
10699	93	52	BASICO	318	t	f
10700	93	34	BASICO	318	t	f
10701	93	35	AVANCADO	321	t	f
10702	93	36	AVANCADO	321	t	f
10703	93	38	AVANCADO	321	t	f
10704	93	39	BASICO	318	t	f
10705	93	40	BASICO	318	t	f
10706	93	41	BASICO	318	t	f
10707	93	43	INTERMEDIARIO	320	t	f
10708	93	44	BASICO	318	t	f
10709	93	13	AVANCADO	321	t	f
10710	93	14	INTERMEDIARIO	320	t	f
10711	93	15	BASICO	318	t	f
10712	93	16	INTERMEDIARIO	320	t	f
10713	93	18	AVANCADO	321	t	f
10714	93	19	BASICO	318	t	f
10715	93	20	AVANCADO	321	t	f
10716	93	21	INTERMEDIARIO	320	t	f
10717	93	26	INTERMEDIARIO	320	t	f
10718	93	53	BASICO	318	t	f
10719	93	54	BASICO	318	t	f
10720	93	55	BASICO	318	t	f
10721	93	56	BASICO	318	t	f
10722	93	58	INTERMEDIARIO	320	t	f
10723	93	61	BASICO	318	t	f
10724	93	62	BASICO	318	t	f
10725	93	89	INTERMEDIARIO	320	t	f
10726	93	93	BASICO	318	t	f
10727	93	94	BASICO	318	t	f
10728	93	115	BASICO	318	t	f
10729	93	116	BASICO	318	t	f
10730	93	117	BASICO	318	t	f
10731	93	118	BASICO	318	t	f
10732	93	119	BASICO	318	t	f
10733	93	2	BASICO	318	t	f
10734	93	9	BASICO	318	t	f
10735	93	10	BASICO	318	t	f
10736	93	63	BASICO	318	t	f
10737	93	64	BASICO	318	t	f
10738	93	66	INTERMEDIARIO	320	t	f
10739	93	68	BASICO	318	t	f
10740	93	72	INTERMEDIARIO	320	t	f
10741	93	75	BASICO	318	t	f
10742	93	82	INTERMEDIARIO	320	t	f
10743	93	109	BASICO	318	t	f
10744	93	110	BASICO	318	t	f
10745	93	111	BASICO	318	t	f
10746	93	112	BASICO	318	t	f
10747	303	98	BASICO	318	t	f
10748	303	99	BASICO	318	t	f
10749	303	100	BASICO	318	t	f
10750	303	101	BASICO	318	t	f
10751	303	102	BASICO	318	t	f
10752	303	103	BASICO	318	t	f
10753	303	104	BASICO	318	t	f
10754	303	105	BASICO	318	t	f
10755	303	106	BASICO	318	t	f
10756	303	107	BASICO	318	t	f
10757	303	47	BASICO	318	t	f
10758	303	48	BASICO	318	t	f
10759	303	49	BASICO	318	t	f
10760	303	50	BASICO	318	t	f
10761	303	51	BASICO	318	t	f
10762	303	52	BASICO	318	t	f
10763	303	28	BASICO	318	t	f
10764	303	29	INTERMEDIARIO	320	t	f
10765	303	30	BASICO	318	t	f
10766	303	31	BASICO	318	t	f
10767	303	32	BASICO	318	t	f
10768	303	33	BASICO	318	t	f
10769	303	34	BASICO	318	t	f
10770	303	35	INTERMEDIARIO	320	t	f
10771	303	36	INTERMEDIARIO	320	t	f
10772	303	37	INTERMEDIARIO	320	t	f
10773	303	38	BASICO	318	t	f
10774	303	39	BASICO	318	t	f
10775	303	40	AVANCADO	321	t	f
10776	303	41	AVANCADO	321	t	f
10777	303	42	BASICO	318	t	f
10778	303	43	INTERMEDIARIO	320	t	f
10779	303	44	INTERMEDIARIO	320	t	f
10780	303	45	INTERMEDIARIO	320	t	f
10781	303	46	INTERMEDIARIO	320	t	f
10782	303	13	BASICO	318	t	f
10783	303	14	AVANCADO	321	t	f
10784	303	15	AVANCADO	321	t	f
10785	303	16	BASICO	318	t	f
10786	303	17	BASICO	318	t	f
10787	303	18	AVANCADO	321	t	f
10788	303	19	AVANCADO	321	t	f
10789	303	20	INTERMEDIARIO	320	t	f
10790	303	21	INTERMEDIARIO	320	t	f
10791	303	22	BASICO	318	t	f
10792	303	23	BASICO	318	t	f
10793	303	24	BASICO	318	t	f
10794	303	25	BASICO	318	t	f
10795	303	26	INTERMEDIARIO	320	t	f
10796	303	27	BASICO	318	t	f
10797	303	53	INTERMEDIARIO	320	t	f
10798	303	54	INTERMEDIARIO	320	t	f
10799	303	55	INTERMEDIARIO	320	t	f
10800	303	56	INTERMEDIARIO	320	t	f
10801	303	57	INTERMEDIARIO	320	t	f
10802	303	58	INTERMEDIARIO	320	t	f
10803	303	59	INTERMEDIARIO	320	t	f
10804	303	60	INTERMEDIARIO	320	t	f
10805	303	61	INTERMEDIARIO	320	t	f
10806	303	62	INTERMEDIARIO	320	t	f
10807	303	83	BASICO	318	t	f
10808	303	84	BASICO	318	t	f
10809	303	85	BASICO	318	t	f
10810	303	86	BASICO	318	t	f
10811	303	87	BASICO	318	t	f
10812	303	88	BASICO	318	t	f
10813	303	89	BASICO	318	t	f
10814	303	90	BASICO	318	t	f
10815	303	91	BASICO	318	t	f
10816	303	92	BASICO	318	t	f
10817	303	93	BASICO	318	t	f
10818	303	94	BASICO	318	t	f
10819	303	95	BASICO	318	t	f
10820	303	96	BASICO	318	t	f
10821	303	97	BASICO	318	t	f
10822	303	130	BASICO	318	t	f
10823	303	113	INTERMEDIARIO	320	t	f
10824	303	114	AVANCADO	321	t	f
10825	303	115	AVANCADO	321	t	f
10826	303	116	AVANCADO	321	t	f
10827	303	117	AVANCADO	321	t	f
10828	303	118	AVANCADO	321	t	f
10829	303	119	INTERMEDIARIO	320	t	f
10830	303	120	INTERMEDIARIO	320	t	f
10831	303	121	BASICO	318	t	f
10832	303	122	BASICO	318	t	f
10833	303	123	INTERMEDIARIO	320	t	f
10834	303	124	INTERMEDIARIO	320	t	f
10835	303	125	BASICO	318	t	f
10836	303	126	BASICO	318	t	f
10837	303	127	BASICO	318	t	f
10838	303	129	INTERMEDIARIO	320	t	f
10839	303	1	BASICO	318	t	f
10840	303	2	BASICO	318	t	f
10841	303	3	BASICO	318	t	f
10842	303	4	BASICO	318	t	f
10843	303	5	BASICO	318	t	f
10844	303	6	BASICO	318	t	f
10845	303	7	BASICO	318	t	f
10846	303	8	BASICO	318	t	f
10847	303	9	BASICO	318	t	f
10848	303	10	BASICO	318	t	f
10849	303	11	BASICO	318	t	f
10850	303	12	BASICO	318	t	f
10851	303	63	INTERMEDIARIO	320	t	f
10852	303	64	BASICO	318	t	f
10853	303	65	INTERMEDIARIO	320	t	f
10854	303	66	INTERMEDIARIO	320	t	f
10855	303	67	BASICO	318	t	f
10856	303	68	BASICO	318	t	f
10857	303	69	BASICO	318	t	f
10858	303	70	BASICO	318	t	f
10859	303	71	INTERMEDIARIO	320	t	f
10860	303	72	INTERMEDIARIO	320	t	f
10861	303	74	BASICO	318	t	f
10862	303	75	INTERMEDIARIO	320	t	f
10863	303	76	BASICO	318	t	f
10864	303	77	BASICO	318	t	f
10865	303	78	BASICO	318	t	f
10866	303	79	BASICO	318	t	f
10867	303	81	BASICO	318	t	f
10868	303	82	BASICO	318	t	f
10869	303	108	INTERMEDIARIO	320	t	f
10870	303	109	INTERMEDIARIO	320	t	f
10871	303	110	INTERMEDIARIO	320	t	f
10872	303	111	INTERMEDIARIO	320	t	f
10873	303	112	INTERMEDIARIO	320	t	f
10874	207	100	INTERMEDIARIO	320	t	f
10875	207	107	INTERMEDIARIO	320	t	f
10876	207	48	BASICO	318	t	f
10877	207	49	BASICO	318	t	f
10878	207	52	INTERMEDIARIO	320	t	f
10879	207	34	BASICO	318	t	f
10880	207	40	INTERMEDIARIO	320	t	f
10881	207	41	INTERMEDIARIO	320	t	f
10882	207	42	BASICO	318	t	f
10883	207	43	BASICO	318	t	f
10884	207	44	INTERMEDIARIO	320	t	f
10885	207	15	INTERMEDIARIO	320	t	f
10886	207	16	AVANCADO	321	t	f
10887	207	19	AVANCADO	321	t	f
10888	207	23	BASICO	318	t	f
10889	207	26	AVANCADO	321	t	f
10890	207	55	INTERMEDIARIO	320	t	f
10891	207	56	INTERMEDIARIO	320	t	f
10892	207	58	INTERMEDIARIO	320	t	f
10893	207	59	AVANCADO	321	t	f
10894	207	60	INTERMEDIARIO	320	t	f
10895	207	61	AVANCADO	321	t	f
10896	207	84	BASICO	318	t	f
10897	207	114	BASICO	318	t	f
10898	207	115	AVANCADO	321	t	f
10899	207	116	INTERMEDIARIO	320	t	f
10900	207	117	INTERMEDIARIO	320	t	f
10901	207	118	INTERMEDIARIO	320	t	f
10902	207	119	INTERMEDIARIO	320	t	f
10903	207	120	INTERMEDIARIO	320	t	f
10904	207	1	INTERMEDIARIO	320	t	f
10905	207	2	INTERMEDIARIO	320	t	f
10906	207	3	INTERMEDIARIO	320	t	f
10907	207	7	BASICO	318	t	f
10908	207	8	INTERMEDIARIO	320	t	f
10909	207	65	INTERMEDIARIO	320	t	f
10910	207	66	INTERMEDIARIO	320	t	f
10911	207	68	INTERMEDIARIO	320	t	f
10912	207	78	BASICO	318	t	f
10913	207	79	INTERMEDIARIO	320	t	f
10914	207	109	AVANCADO	321	t	f
10915	207	110	AVANCADO	321	t	f
10916	207	111	AVANCADO	321	t	f
10917	74	105	BASICO	318	t	f
10918	74	106	BASICO	318	t	f
10919	74	107	BASICO	318	t	f
10920	74	50	BASICO	318	t	f
10921	74	29	BASICO	318	t	f
10922	74	40	BASICO	318	t	f
10923	74	41	INTERMEDIARIO	320	t	f
10924	74	44	BASICO	318	t	f
10925	74	16	INTERMEDIARIO	320	t	f
10926	74	19	BASICO	318	t	f
10927	74	21	BASICO	318	t	f
10928	74	26	INTERMEDIARIO	320	t	f
10929	74	55	BASICO	318	t	f
10930	74	56	BASICO	318	t	f
10931	74	58	BASICO	318	t	f
10932	74	114	BASICO	318	t	f
10933	74	115	BASICO	318	t	f
10934	74	117	BASICO	318	t	f
10935	74	119	BASICO	318	t	f
10936	74	129	INTERMEDIARIO	320	t	f
10937	74	4	BASICO	318	t	f
10938	74	8	BASICO	318	t	f
10939	74	9	BASICO	318	t	f
10940	74	12	BASICO	318	t	f
10941	74	63	BASICO	318	t	f
10942	74	64	BASICO	318	t	f
10943	74	65	INTERMEDIARIO	320	t	f
10944	74	66	INTERMEDIARIO	320	t	f
10945	74	72	INTERMEDIARIO	320	t	f
10946	74	108	BASICO	318	t	f
10947	74	109	BASICO	318	t	f
10948	74	110	BASICO	318	t	f
10949	74	111	BASICO	318	t	f
10950	169	99	BASICO	318	t	f
10951	169	103	BASICO	318	t	f
10952	169	104	BASICO	318	t	f
10953	169	106	BASICO	318	t	f
10954	169	107	BASICO	318	t	f
10955	169	47	BASICO	318	t	f
10956	169	48	BASICO	318	t	f
10957	169	49	BASICO	318	t	f
10958	169	50	AVANCADO	321	t	f
10959	169	51	BASICO	318	t	f
10960	169	52	AVANCADO	321	t	f
10961	169	34	BASICO	318	t	f
10962	169	35	BASICO	318	t	f
10963	169	36	INTERMEDIARIO	320	t	f
10964	169	38	BASICO	318	t	f
10965	169	41	BASICO	318	t	f
10966	169	44	BASICO	318	t	f
10967	169	14	BASICO	318	t	f
10968	169	15	BASICO	318	t	f
10969	169	19	BASICO	318	t	f
10970	169	21	BASICO	318	t	f
10971	169	53	INTERMEDIARIO	320	t	f
10972	169	55	INTERMEDIARIO	320	t	f
10973	169	56	INTERMEDIARIO	320	t	f
10974	169	58	INTERMEDIARIO	320	t	f
10975	169	59	BASICO	318	t	f
10976	169	62	BASICO	318	t	f
10977	169	115	BASICO	318	t	f
10978	169	117	BASICO	318	t	f
10979	169	3	BASICO	318	t	f
10980	169	10	BASICO	318	t	f
10981	169	65	BASICO	318	t	f
10982	169	72	BASICO	318	t	f
10983	169	74	BASICO	318	t	f
10984	169	82	BASICO	318	t	f
10985	214	103	INTERMEDIARIO	320	t	f
10986	214	105	BASICO	318	t	f
10987	214	106	INTERMEDIARIO	320	t	f
10988	214	36	BASICO	318	t	f
10989	284	98	AVANCADO	321	t	f
10990	284	102	BASICO	318	t	f
10991	284	103	BASICO	318	t	f
10992	284	104	BASICO	318	t	f
10993	284	105	INTERMEDIARIO	320	t	f
10994	284	106	INTERMEDIARIO	320	t	f
10995	284	49	AVANCADO	321	t	f
10996	284	51	BASICO	318	t	f
10997	284	52	BASICO	318	t	f
10998	284	29	AVANCADO	321	t	f
10999	284	30	BASICO	318	t	f
11000	284	35	INTERMEDIARIO	320	t	f
11001	284	37	INTERMEDIARIO	320	t	f
11002	284	38	AVANCADO	321	t	f
11003	284	40	INTERMEDIARIO	320	t	f
11004	284	41	INTERMEDIARIO	320	t	f
11005	284	44	BASICO	318	t	f
11006	284	23	BASICO	318	t	f
11007	284	53	INTERMEDIARIO	320	t	f
11008	284	54	BASICO	318	t	f
11009	284	55	BASICO	318	t	f
11010	284	56	BASICO	318	t	f
11011	284	59	INTERMEDIARIO	320	t	f
11012	284	60	BASICO	318	t	f
11013	284	61	BASICO	318	t	f
11014	284	86	INTERMEDIARIO	320	t	f
11015	284	87	BASICO	318	t	f
11016	284	91	BASICO	318	t	f
11017	284	97	BASICO	318	t	f
11018	284	115	BASICO	318	t	f
11019	284	117	INTERMEDIARIO	320	t	f
11020	284	123	BASICO	318	t	f
11021	284	129	BASICO	318	t	f
11022	284	1	BASICO	318	t	f
11023	284	4	BASICO	318	t	f
11024	284	7	BASICO	318	t	f
11025	284	8	INTERMEDIARIO	320	t	f
11026	284	9	INTERMEDIARIO	320	t	f
11027	284	63	BASICO	318	t	f
11028	284	64	INTERMEDIARIO	320	t	f
11029	284	65	BASICO	318	t	f
11030	284	66	BASICO	318	t	f
11031	284	71	BASICO	318	t	f
11032	284	72	BASICO	318	t	f
11033	284	109	BASICO	318	t	f
11034	284	110	INTERMEDIARIO	320	t	f
11035	284	111	INTERMEDIARIO	320	t	f
11036	134	103	BASICO	318	t	f
11037	134	105	BASICO	318	t	f
11038	134	106	INTERMEDIARIO	320	t	f
11039	134	65	BASICO	318	t	f
11040	134	72	BASICO	318	t	f
11041	134	110	BASICO	318	t	f
11042	103	99	BASICO	318	t	f
11043	103	100	BASICO	318	t	f
11044	103	103	BASICO	318	t	f
11045	103	106	INTERMEDIARIO	320	t	f
11046	103	48	BASICO	318	t	f
11047	103	28	BASICO	318	t	f
11048	103	35	BASICO	318	t	f
11049	103	36	BASICO	318	t	f
11050	103	38	BASICO	318	t	f
11051	103	39	BASICO	318	t	f
11052	103	41	BASICO	318	t	f
11053	103	16	BASICO	318	t	f
11054	103	56	BASICO	318	t	f
11055	103	58	BASICO	318	t	f
11056	103	1	BASICO	318	t	f
11057	103	2	BASICO	318	t	f
11058	103	6	BASICO	318	t	f
11059	158	103	BASICO	318	t	f
11060	158	106	BASICO	318	t	f
11061	158	28	BASICO	318	t	f
11062	158	35	BASICO	318	t	f
11063	158	36	BASICO	318	t	f
11064	158	38	BASICO	318	t	f
11065	158	39	BASICO	318	t	f
11066	158	16	BASICO	318	t	f
11067	158	55	BASICO	318	t	f
11068	158	56	BASICO	318	t	f
11069	158	58	BASICO	318	t	f
11070	158	122	BASICO	318	t	f
11071	158	1	BASICO	318	t	f
11072	158	63	BASICO	318	t	f
11073	158	64	BASICO	318	t	f
11074	196	98	BASICO	318	t	f
11075	196	99	BASICO	318	t	f
11076	196	100	BASICO	318	t	f
11077	196	101	BASICO	318	t	f
11078	196	102	BASICO	318	t	f
11079	196	103	BASICO	318	t	f
11080	196	104	BASICO	318	t	f
11081	196	105	INTERMEDIARIO	320	t	f
11082	196	106	INTERMEDIARIO	320	t	f
11083	196	107	BASICO	318	t	f
11084	196	47	BASICO	318	t	f
11085	196	48	BASICO	318	t	f
11086	196	49	INTERMEDIARIO	320	t	f
11087	196	50	BASICO	318	t	f
11088	196	51	BASICO	318	t	f
11089	196	52	BASICO	318	t	f
11090	196	28	BASICO	318	t	f
11091	196	29	INTERMEDIARIO	320	t	f
11092	196	30	BASICO	318	t	f
11093	196	31	BASICO	318	t	f
11094	196	32	BASICO	318	t	f
11095	196	33	INTERMEDIARIO	320	t	f
11096	196	34	INTERMEDIARIO	320	t	f
11097	196	35	INTERMEDIARIO	320	t	f
11098	196	36	INTERMEDIARIO	320	t	f
11099	196	37	BASICO	318	t	f
11100	196	38	BASICO	318	t	f
11101	196	39	BASICO	318	t	f
11102	196	40	INTERMEDIARIO	320	t	f
11103	196	41	INTERMEDIARIO	320	t	f
11104	196	42	BASICO	318	t	f
11105	196	43	BASICO	318	t	f
11106	196	44	INTERMEDIARIO	320	t	f
11107	196	45	BASICO	318	t	f
11108	196	46	BASICO	318	t	f
11109	196	13	BASICO	318	t	f
11110	196	14	BASICO	318	t	f
11111	196	15	BASICO	318	t	f
11112	196	16	BASICO	318	t	f
11113	196	17	BASICO	318	t	f
11114	196	18	BASICO	318	t	f
11115	196	19	BASICO	318	t	f
11116	196	20	BASICO	318	t	f
11117	196	21	INTERMEDIARIO	320	t	f
11118	196	22	BASICO	318	t	f
11119	196	23	BASICO	318	t	f
11120	196	24	BASICO	318	t	f
11121	196	25	BASICO	318	t	f
11122	196	26	BASICO	318	t	f
11123	196	27	BASICO	318	t	f
11124	196	53	BASICO	318	t	f
11125	196	54	BASICO	318	t	f
11126	196	55	BASICO	318	t	f
11127	196	56	BASICO	318	t	f
11128	196	57	BASICO	318	t	f
11129	196	58	BASICO	318	t	f
11130	196	59	BASICO	318	t	f
11131	196	60	BASICO	318	t	f
11132	196	61	BASICO	318	t	f
11133	196	62	BASICO	318	t	f
11134	196	83	BASICO	318	t	f
11135	196	84	BASICO	318	t	f
11136	196	85	BASICO	318	t	f
11137	196	86	BASICO	318	t	f
11138	196	87	BASICO	318	t	f
11139	196	88	BASICO	318	t	f
11140	196	89	BASICO	318	t	f
11141	196	90	BASICO	318	t	f
11142	196	91	BASICO	318	t	f
11143	196	92	BASICO	318	t	f
11144	196	93	BASICO	318	t	f
11145	196	94	INTERMEDIARIO	320	t	f
11146	196	95	BASICO	318	t	f
11147	196	96	BASICO	318	t	f
11148	196	97	BASICO	318	t	f
11149	196	130	BASICO	318	t	f
11150	196	113	INTERMEDIARIO	320	t	f
11151	196	114	INTERMEDIARIO	320	t	f
11152	196	115	INTERMEDIARIO	320	t	f
11153	196	116	BASICO	318	t	f
11154	196	117	INTERMEDIARIO	320	t	f
11155	196	118	BASICO	318	t	f
11156	196	119	INTERMEDIARIO	320	t	f
11157	196	120	INTERMEDIARIO	320	t	f
11158	196	121	INTERMEDIARIO	320	t	f
11159	196	122	INTERMEDIARIO	320	t	f
11160	196	123	INTERMEDIARIO	320	t	f
11161	196	124	AVANCADO	321	t	f
11162	196	125	INTERMEDIARIO	320	t	f
11163	196	126	INTERMEDIARIO	320	t	f
11164	196	127	INTERMEDIARIO	320	t	f
11165	196	129	AVANCADO	321	t	f
11166	196	1	BASICO	318	t	f
11167	196	2	BASICO	318	t	f
11168	196	3	BASICO	318	t	f
11169	196	4	BASICO	318	t	f
11170	196	5	BASICO	318	t	f
11171	196	6	BASICO	318	t	f
11172	196	7	BASICO	318	t	f
11173	196	8	INTERMEDIARIO	320	t	f
11174	196	9	BASICO	318	t	f
11175	196	10	BASICO	318	t	f
11176	196	11	BASICO	318	t	f
11177	196	12	BASICO	318	t	f
11178	196	63	INTERMEDIARIO	320	t	f
11179	196	64	INTERMEDIARIO	320	t	f
11180	196	65	AVANCADO	321	t	f
11181	196	66	AVANCADO	321	t	f
11182	196	67	INTERMEDIARIO	320	t	f
11183	196	68	INTERMEDIARIO	320	t	f
11184	196	69	INTERMEDIARIO	320	t	f
11185	196	70	INTERMEDIARIO	320	t	f
11186	196	71	INTERMEDIARIO	320	t	f
11187	196	72	AVANCADO	321	t	f
11188	196	73	AVANCADO	321	t	f
11189	196	74	INTERMEDIARIO	320	t	f
11190	196	75	AVANCADO	321	t	f
11191	196	76	AVANCADO	321	t	f
11192	196	77	AVANCADO	321	t	f
11193	196	78	INTERMEDIARIO	320	t	f
11194	196	79	INTERMEDIARIO	320	t	f
11195	196	81	INTERMEDIARIO	320	t	f
11196	196	82	AVANCADO	321	t	f
11197	196	108	INTERMEDIARIO	320	t	f
11198	196	109	INTERMEDIARIO	320	t	f
11199	196	110	INTERMEDIARIO	320	t	f
11200	196	111	INTERMEDIARIO	320	t	f
11201	196	112	INTERMEDIARIO	320	t	f
11202	49	106	INTERMEDIARIO	320	t	f
11203	49	107	AVANCADO	321	t	f
11204	49	49	BASICO	318	t	f
11205	49	50	AVANCADO	321	t	f
11206	49	29	AVANCADO	321	t	f
11207	49	34	BASICO	318	t	f
11208	49	36	INTERMEDIARIO	320	t	f
11209	49	37	INTERMEDIARIO	320	t	f
11210	49	38	AVANCADO	321	t	f
11211	49	39	AVANCADO	321	t	f
11212	49	40	BASICO	318	t	f
11213	49	41	BASICO	318	t	f
11214	49	43	INTERMEDIARIO	320	t	f
11215	49	45	BASICO	318	t	f
11216	49	14	AVANCADO	321	t	f
11217	49	15	BASICO	318	t	f
11218	49	17	INTERMEDIARIO	320	t	f
11219	49	19	BASICO	318	t	f
11220	49	21	AVANCADO	321	t	f
11221	49	55	AVANCADO	321	t	f
11222	49	56	AVANCADO	321	t	f
11223	49	58	INTERMEDIARIO	320	t	f
11224	49	59	BASICO	318	t	f
11225	49	113	BASICO	318	t	f
11226	49	114	BASICO	318	t	f
11227	49	115	INTERMEDIARIO	320	t	f
11228	49	117	INTERMEDIARIO	320	t	f
11229	49	119	INTERMEDIARIO	320	t	f
11230	49	120	INTERMEDIARIO	320	t	f
11231	49	129	INTERMEDIARIO	320	t	f
11232	49	1	AVANCADO	321	t	f
11233	49	3	INTERMEDIARIO	320	t	f
11234	49	4	BASICO	318	t	f
11235	49	8	BASICO	318	t	f
11236	49	9	BASICO	318	t	f
11237	49	11	INTERMEDIARIO	320	t	f
11238	49	12	INTERMEDIARIO	320	t	f
11239	49	65	INTERMEDIARIO	320	t	f
11240	49	66	INTERMEDIARIO	320	t	f
11241	49	72	BASICO	318	t	f
11242	49	82	BASICO	318	t	f
11243	49	108	BASICO	318	t	f
11244	49	109	BASICO	318	t	f
11245	150	50	BASICO	318	t	f
11246	150	52	BASICO	318	t	f
11247	150	28	BASICO	318	t	f
11248	150	29	BASICO	318	t	f
11249	150	30	BASICO	318	t	f
11250	150	31	BASICO	318	t	f
11251	150	32	BASICO	318	t	f
11252	150	33	BASICO	318	t	f
11253	150	34	BASICO	318	t	f
11254	150	35	INTERMEDIARIO	320	t	f
11255	150	36	AVANCADO	321	t	f
11256	150	37	INTERMEDIARIO	320	t	f
11257	150	38	AVANCADO	321	t	f
11258	150	39	AVANCADO	321	t	f
11259	150	40	INTERMEDIARIO	320	t	f
11260	150	41	INTERMEDIARIO	320	t	f
11261	150	42	BASICO	318	t	f
11262	150	43	INTERMEDIARIO	320	t	f
11263	150	44	INTERMEDIARIO	320	t	f
11264	150	45	BASICO	318	t	f
11265	150	46	BASICO	318	t	f
11266	150	13	BASICO	318	t	f
11267	150	14	BASICO	318	t	f
11268	150	16	BASICO	318	t	f
11269	150	19	BASICO	318	t	f
11270	150	20	BASICO	318	t	f
11271	150	21	BASICO	318	t	f
11272	150	58	BASICO	318	t	f
11273	150	59	BASICO	318	t	f
11274	150	60	BASICO	318	t	f
11275	150	117	BASICO	318	t	f
11276	150	122	BASICO	318	t	f
11277	150	1	INTERMEDIARIO	320	t	f
11278	150	10	BASICO	318	t	f
11279	150	12	BASICO	318	t	f
11280	150	72	BASICO	318	t	f
11281	150	82	BASICO	318	t	f
11282	313	98	INTERMEDIARIO	320	t	f
11283	313	104	BASICO	318	t	f
11284	313	105	INTERMEDIARIO	320	t	f
11285	313	106	INTERMEDIARIO	320	t	f
11286	313	107	INTERMEDIARIO	320	t	f
11287	313	49	BASICO	318	t	f
11288	313	50	INTERMEDIARIO	320	t	f
11289	313	51	BASICO	318	t	f
11290	313	52	BASICO	318	t	f
11291	313	29	INTERMEDIARIO	320	t	f
11292	313	36	BASICO	318	t	f
11293	313	37	BASICO	318	t	f
11294	313	38	INTERMEDIARIO	320	t	f
11295	313	40	INTERMEDIARIO	320	t	f
11296	313	41	INTERMEDIARIO	320	t	f
11297	313	44	INTERMEDIARIO	320	t	f
11298	313	14	BASICO	318	t	f
11299	313	16	AVANCADO	321	t	f
11300	313	19	BASICO	318	t	f
11301	313	21	INTERMEDIARIO	320	t	f
11302	313	26	AVANCADO	321	t	f
11303	313	55	BASICO	318	t	f
11304	313	56	BASICO	318	t	f
11305	313	58	INTERMEDIARIO	320	t	f
11306	313	59	BASICO	318	t	f
11307	313	60	INTERMEDIARIO	320	t	f
11308	313	61	BASICO	318	t	f
11309	313	114	BASICO	318	t	f
11310	313	115	AVANCADO	321	t	f
11311	313	116	AVANCADO	321	t	f
11312	313	117	INTERMEDIARIO	320	t	f
11313	313	118	BASICO	318	t	f
11314	313	119	INTERMEDIARIO	320	t	f
11315	313	120	BASICO	318	t	f
11316	313	129	BASICO	318	t	f
11317	313	1	INTERMEDIARIO	320	t	f
11318	313	4	BASICO	318	t	f
11319	313	8	BASICO	318	t	f
11320	313	9	AVANCADO	321	t	f
11321	313	11	BASICO	318	t	f
11322	313	12	INTERMEDIARIO	320	t	f
11323	313	65	BASICO	318	t	f
11324	313	66	BASICO	318	t	f
11325	313	72	BASICO	318	t	f
11326	313	82	BASICO	318	t	f
11327	313	109	BASICO	318	t	f
11328	313	110	BASICO	318	t	f
11329	313	111	BASICO	318	t	f
11330	220	99	INTERMEDIARIO	320	t	f
11331	220	100	INTERMEDIARIO	320	t	f
11332	220	102	BASICO	318	t	f
11333	220	104	INTERMEDIARIO	320	t	f
11334	220	105	INTERMEDIARIO	320	t	f
11335	220	107	INTERMEDIARIO	320	t	f
11336	220	47	BASICO	318	t	f
11337	220	48	INTERMEDIARIO	320	t	f
11338	220	51	INTERMEDIARIO	320	t	f
11339	220	52	BASICO	318	t	f
11340	220	30	BASICO	318	t	f
11341	220	33	BASICO	318	t	f
11342	220	37	INTERMEDIARIO	320	t	f
11343	220	40	INTERMEDIARIO	320	t	f
11344	220	44	INTERMEDIARIO	320	t	f
11345	220	16	BASICO	318	t	f
11346	220	19	BASICO	318	t	f
11347	220	59	BASICO	318	t	f
11348	220	61	BASICO	318	t	f
11349	220	86	INTERMEDIARIO	320	t	f
11350	220	87	BASICO	318	t	f
11351	220	130	BASICO	318	t	f
11352	220	116	BASICO	318	t	f
11353	220	117	INTERMEDIARIO	320	t	f
11354	220	129	BASICO	318	t	f
11355	220	2	INTERMEDIARIO	320	t	f
11356	220	3	INTERMEDIARIO	320	t	f
11357	220	11	BASICO	318	t	f
11358	220	12	INTERMEDIARIO	320	t	f
11359	220	66	BASICO	318	t	f
11360	220	72	BASICO	318	t	f
11361	220	110	BASICO	318	t	f
11362	117	98	INTERMEDIARIO	320	t	f
11363	117	106	BASICO	318	t	f
11364	117	50	INTERMEDIARIO	320	t	f
11365	117	52	BASICO	318	t	f
11366	117	28	BASICO	318	t	f
11367	117	33	BASICO	318	t	f
11368	117	34	BASICO	318	t	f
11369	117	35	BASICO	318	t	f
11370	117	36	INTERMEDIARIO	320	t	f
11371	117	38	BASICO	318	t	f
11372	117	41	BASICO	318	t	f
11373	117	44	BASICO	318	t	f
11374	117	20	BASICO	318	t	f
11375	117	21	INTERMEDIARIO	320	t	f
11376	117	55	INTERMEDIARIO	320	t	f
11377	117	56	INTERMEDIARIO	320	t	f
11378	117	58	BASICO	318	t	f
11379	117	94	BASICO	318	t	f
11380	117	115	BASICO	318	t	f
11381	117	117	BASICO	318	t	f
11382	117	119	BASICO	318	t	f
11383	117	63	BASICO	318	t	f
11384	117	64	BASICO	318	t	f
11385	174	105	AVANCADO	321	t	f
11386	174	106	AVANCADO	321	t	f
11387	174	47	AVANCADO	321	t	f
11388	174	50	AVANCADO	321	t	f
11389	174	52	AVANCADO	321	t	f
11390	174	29	AVANCADO	321	t	f
11391	174	36	INTERMEDIARIO	320	t	f
11392	174	40	INTERMEDIARIO	320	t	f
11393	174	44	INTERMEDIARIO	320	t	f
11394	174	18	INTERMEDIARIO	320	t	f
11395	174	20	INTERMEDIARIO	320	t	f
11396	174	54	AVANCADO	321	t	f
11397	174	55	AVANCADO	321	t	f
11398	174	58	AVANCADO	321	t	f
11399	174	113	INTERMEDIARIO	320	t	f
11400	174	115	AVANCADO	321	t	f
11401	174	116	INTERMEDIARIO	320	t	f
11402	174	117	AVANCADO	321	t	f
11403	174	119	AVANCADO	321	t	f
11404	174	124	INTERMEDIARIO	320	t	f
11405	174	129	INTERMEDIARIO	320	t	f
11406	174	1	BASICO	318	t	f
11407	174	9	INTERMEDIARIO	320	t	f
11408	174	12	BASICO	318	t	f
11409	174	65	INTERMEDIARIO	320	t	f
11410	174	75	INTERMEDIARIO	320	t	f
11411	174	81	BASICO	318	t	f
11412	174	82	BASICO	318	t	f
11413	174	110	INTERMEDIARIO	320	t	f
11414	51	98	BASICO	318	t	f
11415	51	99	INTERMEDIARIO	320	t	f
11416	51	100	INTERMEDIARIO	320	t	f
11417	51	101	BASICO	318	t	f
11418	51	102	BASICO	318	t	f
11419	7	102	BASICO	318	t	f
11420	51	103	BASICO	318	t	f
11421	51	104	INTERMEDIARIO	320	t	f
11422	51	105	BASICO	318	t	f
11423	51	106	INTERMEDIARIO	320	t	f
11424	51	107	INTERMEDIARIO	320	t	f
11425	51	47	BASICO	318	t	f
11426	51	48	BASICO	318	t	f
11427	51	49	INTERMEDIARIO	320	t	f
11428	51	50	BASICO	318	t	f
11429	51	51	INTERMEDIARIO	320	t	f
11430	51	52	BASICO	318	t	f
11431	51	28	INTERMEDIARIO	320	t	f
11432	51	29	AVANCADO	321	t	f
11433	51	30	BASICO	318	t	f
11434	51	31	INTERMEDIARIO	320	t	f
11435	51	32	BASICO	318	t	f
11436	51	33	AVANCADO	321	t	f
11437	51	34	INTERMEDIARIO	320	t	f
11438	51	35	INTERMEDIARIO	320	t	f
11439	51	36	INTERMEDIARIO	320	t	f
11440	51	37	AVANCADO	321	t	f
11441	51	38	INTERMEDIARIO	320	t	f
11442	51	39	BASICO	318	t	f
11443	51	40	AVANCADO	321	t	f
11444	51	41	AVANCADO	321	t	f
11445	51	42	BASICO	318	t	f
11446	51	43	AVANCADO	321	t	f
11447	51	44	INTERMEDIARIO	320	t	f
11448	51	45	BASICO	318	t	f
11449	51	46	INTERMEDIARIO	320	t	f
11450	51	13	BASICO	318	t	f
11451	51	14	BASICO	318	t	f
11452	51	15	BASICO	318	t	f
11453	51	16	BASICO	318	t	f
11454	51	17	BASICO	318	t	f
11455	51	18	BASICO	318	t	f
11456	51	19	BASICO	318	t	f
11457	51	20	BASICO	318	t	f
11458	51	21	INTERMEDIARIO	320	t	f
11459	51	22	BASICO	318	t	f
11460	51	23	BASICO	318	t	f
11461	51	24	BASICO	318	t	f
11462	51	25	BASICO	318	t	f
11463	51	26	BASICO	318	t	f
11464	51	27	BASICO	318	t	f
11465	51	53	BASICO	318	t	f
11466	51	54	BASICO	318	t	f
11467	51	55	BASICO	318	t	f
11468	51	56	BASICO	318	t	f
11469	51	57	BASICO	318	t	f
11470	51	58	BASICO	318	t	f
11471	51	59	BASICO	318	t	f
11472	51	60	BASICO	318	t	f
11473	51	61	BASICO	318	t	f
11474	51	62	BASICO	318	t	f
11475	51	83	BASICO	318	t	f
11476	51	84	BASICO	318	t	f
11477	51	85	BASICO	318	t	f
11478	51	86	BASICO	318	t	f
11479	51	87	BASICO	318	t	f
11480	51	88	BASICO	318	t	f
11481	51	89	BASICO	318	t	f
11482	51	90	BASICO	318	t	f
11483	51	91	BASICO	318	t	f
11484	51	92	BASICO	318	t	f
11485	51	93	BASICO	318	t	f
11486	51	94	BASICO	318	t	f
11487	51	95	BASICO	318	t	f
11488	51	96	BASICO	318	t	f
11489	51	97	BASICO	318	t	f
11490	51	130	BASICO	318	t	f
11491	51	113	INTERMEDIARIO	320	t	f
11492	51	114	BASICO	318	t	f
11493	51	115	BASICO	318	t	f
11494	51	116	BASICO	318	t	f
11495	51	117	BASICO	318	t	f
11496	51	118	BASICO	318	t	f
11497	51	119	BASICO	318	t	f
11498	51	120	BASICO	318	t	f
11499	51	121	BASICO	318	t	f
11500	51	122	BASICO	318	t	f
11501	51	123	BASICO	318	t	f
11502	51	124	INTERMEDIARIO	320	t	f
11503	51	125	BASICO	318	t	f
11504	51	126	BASICO	318	t	f
11505	51	127	BASICO	318	t	f
11506	51	129	INTERMEDIARIO	320	t	f
11507	51	1	AVANCADO	321	t	f
11508	51	2	INTERMEDIARIO	320	t	f
11509	51	3	BASICO	318	t	f
11510	51	4	BASICO	318	t	f
11511	51	5	BASICO	318	t	f
11512	51	6	BASICO	318	t	f
11513	51	7	BASICO	318	t	f
11514	51	8	INTERMEDIARIO	320	t	f
11515	51	9	BASICO	318	t	f
11516	51	10	INTERMEDIARIO	320	t	f
11517	51	11	BASICO	318	t	f
11518	51	12	INTERMEDIARIO	320	t	f
11519	51	63	BASICO	318	t	f
11520	51	64	BASICO	318	t	f
11521	51	65	AVANCADO	321	t	f
11522	51	66	INTERMEDIARIO	320	t	f
11523	51	67	INTERMEDIARIO	320	t	f
11524	51	68	BASICO	318	t	f
11525	51	69	BASICO	318	t	f
11526	51	70	BASICO	318	t	f
11527	51	72	INTERMEDIARIO	320	t	f
11528	51	73	INTERMEDIARIO	320	t	f
11529	51	74	INTERMEDIARIO	320	t	f
11530	51	75	INTERMEDIARIO	320	t	f
11531	51	76	AVANCADO	321	t	f
11532	51	77	AVANCADO	321	t	f
11533	51	78	BASICO	318	t	f
11534	51	81	BASICO	318	t	f
11535	51	82	AVANCADO	321	t	f
11536	51	108	BASICO	318	t	f
11537	51	110	BASICO	318	t	f
11538	51	111	BASICO	318	t	f
11539	51	112	BASICO	318	t	f
11540	7	98	BASICO	318	t	f
11541	7	99	BASICO	318	t	f
11542	7	100	BASICO	318	t	f
11543	7	101	BASICO	318	t	f
11544	7	103	BASICO	318	t	f
11545	7	104	BASICO	318	t	f
11546	7	105	BASICO	318	t	f
11547	7	106	BASICO	318	t	f
11548	7	107	BASICO	318	t	f
11549	14	98	BASICO	318	t	f
11550	14	99	BASICO	318	t	f
11551	14	100	BASICO	318	t	f
11552	14	101	BASICO	318	t	f
11553	14	102	BASICO	318	t	f
11554	14	103	BASICO	318	t	f
11555	14	104	BASICO	318	t	f
11556	14	105	INTERMEDIARIO	320	t	f
11557	14	106	INTERMEDIARIO	320	t	f
11558	14	107	INTERMEDIARIO	320	t	f
11559	14	47	BASICO	318	t	f
11560	14	48	BASICO	318	t	f
11561	14	49	INTERMEDIARIO	320	t	f
11562	14	50	INTERMEDIARIO	320	t	f
11563	14	51	BASICO	318	t	f
11564	14	52	BASICO	318	t	f
11565	14	28	INTERMEDIARIO	320	t	f
11566	14	29	INTERMEDIARIO	320	t	f
11567	14	30	INTERMEDIARIO	320	t	f
11568	14	31	INTERMEDIARIO	320	t	f
11569	14	32	INTERMEDIARIO	320	t	f
11570	14	33	AVANCADO	321	t	f
11571	14	34	INTERMEDIARIO	320	t	f
11572	14	35	INTERMEDIARIO	320	t	f
11573	14	36	AVANCADO	321	t	f
11574	14	37	AVANCADO	321	t	f
11575	14	38	INTERMEDIARIO	320	t	f
11576	14	39	BASICO	318	t	f
11577	14	40	INTERMEDIARIO	320	t	f
11578	14	41	INTERMEDIARIO	320	t	f
11579	14	42	BASICO	318	t	f
11580	14	43	INTERMEDIARIO	320	t	f
11581	14	44	INTERMEDIARIO	320	t	f
11582	14	45	BASICO	318	t	f
11583	14	46	BASICO	318	t	f
11584	14	13	INTERMEDIARIO	320	t	f
11585	14	14	INTERMEDIARIO	320	t	f
11586	14	15	BASICO	318	t	f
11587	14	16	INTERMEDIARIO	320	t	f
11588	14	17	INTERMEDIARIO	320	t	f
11589	14	18	INTERMEDIARIO	320	t	f
11590	14	19	BASICO	318	t	f
11591	14	20	AVANCADO	321	t	f
11592	14	21	AVANCADO	321	t	f
11593	14	22	BASICO	318	t	f
11594	14	23	INTERMEDIARIO	320	t	f
11595	14	24	BASICO	318	t	f
11596	14	25	BASICO	318	t	f
11597	14	26	BASICO	318	t	f
11598	14	27	BASICO	318	t	f
11599	14	55	INTERMEDIARIO	320	t	f
11600	14	56	AVANCADO	321	t	f
11601	14	57	BASICO	318	t	f
11602	14	58	AVANCADO	321	t	f
11603	14	59	BASICO	318	t	f
11604	14	61	BASICO	318	t	f
11605	14	85	BASICO	318	t	f
11606	14	94	BASICO	318	t	f
11607	14	113	BASICO	318	t	f
11608	14	115	BASICO	318	t	f
11609	14	117	BASICO	318	t	f
11610	14	118	BASICO	318	t	f
11611	14	119	BASICO	318	t	f
11612	14	124	BASICO	318	t	f
11613	14	129	BASICO	318	t	f
11614	14	1	INTERMEDIARIO	320	t	f
11615	14	3	BASICO	318	t	f
11616	14	7	BASICO	318	t	f
11617	14	9	BASICO	318	t	f
11618	14	10	BASICO	318	t	f
11619	14	12	INTERMEDIARIO	320	t	f
11620	14	63	BASICO	318	t	f
11621	14	64	BASICO	318	t	f
11622	14	65	BASICO	318	t	f
11623	14	66	BASICO	318	t	f
11624	14	72	BASICO	318	t	f
11625	14	75	BASICO	318	t	f
11626	14	82	INTERMEDIARIO	320	t	f
11627	14	108	BASICO	318	t	f
11628	14	109	BASICO	318	t	f
11629	14	110	BASICO	318	t	f
11630	14	111	BASICO	318	t	f
11631	228	98	BASICO	318	t	f
11632	228	99	BASICO	318	t	f
11633	228	100	BASICO	318	t	f
11634	228	101	BASICO	318	t	f
11635	228	102	BASICO	318	t	f
11636	228	103	BASICO	318	t	f
11637	228	104	BASICO	318	t	f
11638	228	105	INTERMEDIARIO	320	t	f
11639	228	106	INTERMEDIARIO	320	t	f
11640	228	107	BASICO	318	t	f
11641	228	47	BASICO	318	t	f
11642	228	48	BASICO	318	t	f
11643	228	49	BASICO	318	t	f
11644	228	50	BASICO	318	t	f
11645	228	51	BASICO	318	t	f
11646	228	52	BASICO	318	t	f
11647	228	28	BASICO	318	t	f
11648	228	29	BASICO	318	t	f
11649	228	30	BASICO	318	t	f
11650	228	31	BASICO	318	t	f
11651	228	32	BASICO	318	t	f
11652	228	33	BASICO	318	t	f
11653	228	34	BASICO	318	t	f
11654	228	35	BASICO	318	t	f
11655	228	36	BASICO	318	t	f
11656	228	37	BASICO	318	t	f
11657	228	38	BASICO	318	t	f
11658	228	39	BASICO	318	t	f
11659	228	40	BASICO	318	t	f
11660	228	41	BASICO	318	t	f
11661	228	42	BASICO	318	t	f
11662	228	43	BASICO	318	t	f
11663	228	44	BASICO	318	t	f
11664	228	45	BASICO	318	t	f
11665	228	46	BASICO	318	t	f
11666	228	13	BASICO	318	t	f
11667	228	14	BASICO	318	t	f
11668	228	15	BASICO	318	t	f
11669	228	16	BASICO	318	t	f
11670	228	17	BASICO	318	t	f
11671	228	18	BASICO	318	t	f
11672	228	19	BASICO	318	t	f
11673	228	20	BASICO	318	t	f
11674	228	21	BASICO	318	t	f
11675	228	22	BASICO	318	t	f
11676	228	23	BASICO	318	t	f
11677	228	24	BASICO	318	t	f
11678	228	25	BASICO	318	t	f
11679	228	26	BASICO	318	t	f
11680	228	27	BASICO	318	t	f
11681	228	53	BASICO	318	t	f
11682	228	54	BASICO	318	t	f
11683	228	55	BASICO	318	t	f
11684	228	56	BASICO	318	t	f
11685	228	57	BASICO	318	t	f
11686	228	58	BASICO	318	t	f
11687	228	59	BASICO	318	t	f
11688	228	60	BASICO	318	t	f
11689	228	61	BASICO	318	t	f
11690	228	62	BASICO	318	t	f
11691	228	83	BASICO	318	t	f
11692	228	84	BASICO	318	t	f
11693	228	85	BASICO	318	t	f
11694	228	86	BASICO	318	t	f
11695	228	87	BASICO	318	t	f
11696	228	88	BASICO	318	t	f
11697	228	89	BASICO	318	t	f
11698	228	90	BASICO	318	t	f
11699	228	91	BASICO	318	t	f
11700	228	92	BASICO	318	t	f
11701	228	93	BASICO	318	t	f
11702	228	94	BASICO	318	t	f
11703	228	95	BASICO	318	t	f
11704	228	96	BASICO	318	t	f
11705	228	97	BASICO	318	t	f
11706	228	130	BASICO	318	t	f
11707	228	113	BASICO	318	t	f
11708	228	114	BASICO	318	t	f
11709	228	115	BASICO	318	t	f
11710	228	116	BASICO	318	t	f
11711	228	117	BASICO	318	t	f
11712	228	118	BASICO	318	t	f
11713	228	119	BASICO	318	t	f
11714	228	120	BASICO	318	t	f
11715	228	121	BASICO	318	t	f
11716	228	122	BASICO	318	t	f
11717	228	123	BASICO	318	t	f
11718	228	124	BASICO	318	t	f
11719	228	125	BASICO	318	t	f
11720	228	126	BASICO	318	t	f
11721	228	127	BASICO	318	t	f
11722	228	129	BASICO	318	t	f
11723	228	1	BASICO	318	t	f
11724	228	2	BASICO	318	t	f
11725	228	3	BASICO	318	t	f
11726	228	4	BASICO	318	t	f
11727	228	5	BASICO	318	t	f
11728	228	6	BASICO	318	t	f
11729	228	7	BASICO	318	t	f
11730	228	8	BASICO	318	t	f
11731	228	9	BASICO	318	t	f
11732	228	10	BASICO	318	t	f
11733	228	11	BASICO	318	t	f
11734	228	12	BASICO	318	t	f
11735	228	63	BASICO	318	t	f
11736	228	64	BASICO	318	t	f
11737	228	65	BASICO	318	t	f
11738	228	66	BASICO	318	t	f
11739	228	67	BASICO	318	t	f
11740	228	68	BASICO	318	t	f
11741	228	69	BASICO	318	t	f
11742	228	70	BASICO	318	t	f
11743	228	71	BASICO	318	t	f
11744	228	72	BASICO	318	t	f
11745	228	73	BASICO	318	t	f
11746	228	74	BASICO	318	t	f
11747	228	75	BASICO	318	t	f
11748	228	76	BASICO	318	t	f
11749	228	77	BASICO	318	t	f
11750	228	78	BASICO	318	t	f
11751	228	79	BASICO	318	t	f
11752	228	81	BASICO	318	t	f
11753	228	82	BASICO	318	t	f
11754	228	108	BASICO	318	t	f
11755	228	109	BASICO	318	t	f
11756	228	110	BASICO	318	t	f
11757	228	111	BASICO	318	t	f
11758	228	112	BASICO	318	t	f
11759	125	103	BASICO	318	t	f
11760	125	105	INTERMEDIARIO	320	t	f
11761	125	106	INTERMEDIARIO	320	t	f
11762	125	50	BASICO	318	t	f
11763	125	36	BASICO	318	t	f
11764	125	43	BASICO	318	t	f
11765	125	14	BASICO	318	t	f
11766	125	18	BASICO	318	t	f
11767	125	25	BASICO	318	t	f
11768	125	55	BASICO	318	t	f
11769	125	56	BASICO	318	t	f
11770	125	84	INTERMEDIARIO	320	t	f
11771	125	90	INTERMEDIARIO	320	t	f
11772	125	96	INTERMEDIARIO	320	t	f
11773	125	97	AVANCADO	321	t	f
11774	125	117	INTERMEDIARIO	320	t	f
11775	125	119	INTERMEDIARIO	320	t	f
11776	125	129	INTERMEDIARIO	320	t	f
11777	125	7	BASICO	318	t	f
11778	125	9	BASICO	318	t	f
11779	125	63	INTERMEDIARIO	320	t	f
11780	125	71	INTERMEDIARIO	320	t	f
11781	125	72	BASICO	318	t	f
11782	125	74	BASICO	318	t	f
11783	125	110	BASICO	318	t	f
11784	239	33	INTERMEDIARIO	320	t	f
11785	239	34	INTERMEDIARIO	320	t	f
11786	239	35	INTERMEDIARIO	320	t	f
11787	239	36	INTERMEDIARIO	320	t	f
11788	239	37	INTERMEDIARIO	320	t	f
11789	239	44	INTERMEDIARIO	320	t	f
11790	239	63	INTERMEDIARIO	320	t	f
11791	239	64	INTERMEDIARIO	320	t	f
11792	239	65	AVANCADO	321	t	f
11793	239	66	AVANCADO	321	t	f
11794	239	67	AVANCADO	321	t	f
11795	239	68	INTERMEDIARIO	320	t	f
11796	239	69	INTERMEDIARIO	320	t	f
11797	239	70	INTERMEDIARIO	320	t	f
11798	239	71	INTERMEDIARIO	320	t	f
11799	239	72	AVANCADO	321	t	f
11800	239	73	INTERMEDIARIO	320	t	f
11801	239	74	INTERMEDIARIO	320	t	f
11802	239	75	AVANCADO	321	t	f
11803	239	76	AVANCADO	321	t	f
11804	239	78	INTERMEDIARIO	320	t	f
11805	239	79	INTERMEDIARIO	320	t	f
11806	239	81	AVANCADO	321	t	f
11807	239	82	AVANCADO	321	t	f
11808	86	99	BASICO	318	t	f
11809	86	103	BASICO	318	t	f
11810	86	48	BASICO	318	t	f
11811	86	38	BASICO	318	t	f
11812	86	14	BASICO	318	t	f
11813	86	21	BASICO	318	t	f
11814	86	56	BASICO	318	t	f
11815	86	115	BASICO	318	t	f
11816	86	129	BASICO	318	t	f
11817	86	65	BASICO	318	t	f
11818	86	72	BASICO	318	t	f
11819	86	82	BASICO	318	t	f
11820	60	98	INTERMEDIARIO	320	t	f
11821	60	99	INTERMEDIARIO	320	t	f
11822	60	100	INTERMEDIARIO	320	t	f
11823	60	101	INTERMEDIARIO	320	t	f
11824	60	102	INTERMEDIARIO	320	t	f
11825	60	103	INTERMEDIARIO	320	t	f
11826	60	104	BASICO	318	t	f
11827	60	105	INTERMEDIARIO	320	t	f
11828	60	106	AVANCADO	321	t	f
11829	60	107	AVANCADO	321	t	f
11830	60	47	BASICO	318	t	f
11831	60	48	BASICO	318	t	f
11832	60	49	BASICO	318	t	f
11833	60	50	INTERMEDIARIO	320	t	f
11834	60	51	INTERMEDIARIO	320	t	f
11835	60	52	INTERMEDIARIO	320	t	f
11836	60	28	INTERMEDIARIO	320	t	f
11837	60	29	INTERMEDIARIO	320	t	f
11838	60	30	INTERMEDIARIO	320	t	f
11839	60	31	INTERMEDIARIO	320	t	f
11840	60	32	INTERMEDIARIO	320	t	f
11841	60	33	BASICO	318	t	f
11842	60	34	BASICO	318	t	f
11843	60	35	INTERMEDIARIO	320	t	f
11844	60	36	INTERMEDIARIO	320	t	f
11845	60	38	BASICO	318	t	f
11846	60	39	INTERMEDIARIO	320	t	f
11847	60	40	INTERMEDIARIO	320	t	f
11848	60	41	INTERMEDIARIO	320	t	f
11849	60	42	BASICO	318	t	f
11850	60	43	INTERMEDIARIO	320	t	f
11851	60	44	BASICO	318	t	f
11852	60	45	BASICO	318	t	f
11853	60	46	BASICO	318	t	f
11854	60	13	BASICO	318	t	f
11855	60	14	INTERMEDIARIO	320	t	f
11856	60	15	INTERMEDIARIO	320	t	f
11857	60	16	INTERMEDIARIO	320	t	f
11858	60	17	BASICO	318	t	f
11859	60	18	BASICO	318	t	f
11860	60	19	BASICO	318	t	f
11861	60	20	BASICO	318	t	f
11862	60	21	BASICO	318	t	f
11863	60	22	BASICO	318	t	f
11864	60	23	BASICO	318	t	f
11865	60	24	BASICO	318	t	f
11866	60	25	BASICO	318	t	f
11867	60	26	BASICO	318	t	f
11868	60	27	BASICO	318	t	f
11869	60	53	INTERMEDIARIO	320	t	f
11870	60	54	INTERMEDIARIO	320	t	f
11871	60	55	INTERMEDIARIO	320	t	f
11872	60	56	INTERMEDIARIO	320	t	f
11873	60	58	INTERMEDIARIO	320	t	f
11874	60	59	INTERMEDIARIO	320	t	f
11875	60	60	INTERMEDIARIO	320	t	f
11876	60	61	INTERMEDIARIO	320	t	f
11877	60	62	INTERMEDIARIO	320	t	f
11878	60	83	BASICO	318	t	f
11879	60	84	BASICO	318	t	f
11880	60	85	BASICO	318	t	f
11881	60	86	BASICO	318	t	f
11882	60	87	INTERMEDIARIO	320	t	f
11883	60	88	INTERMEDIARIO	320	t	f
11884	60	89	BASICO	318	t	f
11885	60	90	BASICO	318	t	f
11886	60	91	INTERMEDIARIO	320	t	f
11887	60	92	INTERMEDIARIO	320	t	f
11888	60	93	BASICO	318	t	f
11889	60	94	BASICO	318	t	f
11890	60	95	BASICO	318	t	f
11891	60	96	BASICO	318	t	f
11892	60	97	BASICO	318	t	f
11893	60	130	BASICO	318	t	f
11894	60	113	BASICO	318	t	f
11895	60	114	BASICO	318	t	f
11896	60	115	INTERMEDIARIO	320	t	f
11897	60	116	BASICO	318	t	f
11898	60	117	INTERMEDIARIO	320	t	f
11899	60	118	BASICO	318	t	f
11900	60	119	INTERMEDIARIO	320	t	f
11901	60	120	BASICO	318	t	f
11902	60	121	BASICO	318	t	f
11903	60	122	BASICO	318	t	f
11904	60	123	BASICO	318	t	f
11905	60	124	BASICO	318	t	f
11906	60	125	BASICO	318	t	f
11907	60	126	BASICO	318	t	f
11908	60	127	BASICO	318	t	f
11909	60	129	INTERMEDIARIO	320	t	f
11910	60	1	INTERMEDIARIO	320	t	f
11911	60	2	BASICO	318	t	f
11912	60	3	BASICO	318	t	f
11913	60	4	BASICO	318	t	f
11914	60	5	BASICO	318	t	f
11915	60	6	BASICO	318	t	f
11916	60	7	INTERMEDIARIO	320	t	f
11917	60	8	BASICO	318	t	f
11918	60	9	BASICO	318	t	f
11919	60	10	BASICO	318	t	f
11920	60	11	INTERMEDIARIO	320	t	f
11921	60	12	INTERMEDIARIO	320	t	f
11922	60	63	INTERMEDIARIO	320	t	f
11923	60	64	INTERMEDIARIO	320	t	f
11924	60	65	BASICO	318	t	f
11925	60	66	BASICO	318	t	f
11926	60	67	BASICO	318	t	f
11927	60	68	BASICO	318	t	f
11928	60	69	BASICO	318	t	f
11929	60	70	BASICO	318	t	f
11930	60	71	BASICO	318	t	f
11931	60	72	BASICO	318	t	f
11932	60	73	BASICO	318	t	f
11933	60	74	BASICO	318	t	f
11934	60	75	BASICO	318	t	f
11935	60	76	BASICO	318	t	f
11936	60	77	BASICO	318	t	f
11937	60	78	BASICO	318	t	f
11938	60	79	BASICO	318	t	f
11939	60	81	BASICO	318	t	f
11940	60	82	BASICO	318	t	f
11941	60	108	BASICO	318	t	f
11942	60	109	INTERMEDIARIO	320	t	f
11943	60	110	BASICO	318	t	f
11944	60	111	BASICO	318	t	f
11945	60	112	BASICO	318	t	f
11946	149	103	AVANCADO	321	t	f
11947	149	104	AVANCADO	321	t	f
11948	149	105	AVANCADO	321	t	f
11949	149	106	AVANCADO	321	t	f
11950	149	50	AVANCADO	321	t	f
11951	149	51	AVANCADO	321	t	f
11952	149	52	INTERMEDIARIO	320	t	f
11953	149	29	AVANCADO	321	t	f
11954	149	37	AVANCADO	321	t	f
11955	149	40	INTERMEDIARIO	320	t	f
11956	149	41	INTERMEDIARIO	320	t	f
11957	149	14	INTERMEDIARIO	320	t	f
11958	149	16	BASICO	318	t	f
11959	149	18	INTERMEDIARIO	320	t	f
11960	149	20	INTERMEDIARIO	320	t	f
11961	149	21	INTERMEDIARIO	320	t	f
11962	149	53	INTERMEDIARIO	320	t	f
11963	149	59	INTERMEDIARIO	320	t	f
11964	149	62	INTERMEDIARIO	320	t	f
11965	149	85	INTERMEDIARIO	320	t	f
11966	149	94	INTERMEDIARIO	320	t	f
11967	149	117	INTERMEDIARIO	320	t	f
11968	149	129	INTERMEDIARIO	320	t	f
11969	149	7	BASICO	318	t	f
11970	149	10	BASICO	318	t	f
11971	149	63	BASICO	318	t	f
11972	149	65	INTERMEDIARIO	320	t	f
11973	149	72	INTERMEDIARIO	320	t	f
11974	149	76	INTERMEDIARIO	320	t	f
11975	149	108	INTERMEDIARIO	320	t	f
11976	149	109	INTERMEDIARIO	320	t	f
11977	149	110	BASICO	318	t	f
11978	149	111	BASICO	318	t	f
11979	149	112	BASICO	318	t	f
11980	47	98	BASICO	318	t	f
11981	47	99	INTERMEDIARIO	320	t	f
11982	47	100	BASICO	318	t	f
11983	47	101	BASICO	318	t	f
11984	47	102	INTERMEDIARIO	320	t	f
11985	47	103	INTERMEDIARIO	320	t	f
11986	47	104	INTERMEDIARIO	320	t	f
11987	47	105	BASICO	318	t	f
11988	47	106	INTERMEDIARIO	320	t	f
11989	47	107	INTERMEDIARIO	320	t	f
11990	47	47	BASICO	318	t	f
11991	47	48	BASICO	318	t	f
11992	47	49	INTERMEDIARIO	320	t	f
11993	47	50	AVANCADO	321	t	f
11994	47	51	INTERMEDIARIO	320	t	f
11995	47	52	INTERMEDIARIO	320	t	f
11996	47	29	INTERMEDIARIO	320	t	f
11997	47	30	INTERMEDIARIO	320	t	f
11998	47	31	BASICO	318	t	f
11999	47	32	BASICO	318	t	f
12000	47	33	INTERMEDIARIO	320	t	f
12001	47	35	BASICO	318	t	f
12002	47	36	INTERMEDIARIO	320	t	f
12003	47	38	INTERMEDIARIO	320	t	f
12004	47	39	BASICO	318	t	f
12005	47	40	INTERMEDIARIO	320	t	f
12006	47	41	INTERMEDIARIO	320	t	f
12007	47	42	INTERMEDIARIO	320	t	f
12008	47	43	BASICO	318	t	f
12009	47	44	INTERMEDIARIO	320	t	f
12010	47	45	INTERMEDIARIO	320	t	f
12011	47	46	AVANCADO	321	t	f
12012	47	13	BASICO	318	t	f
12013	47	14	INTERMEDIARIO	320	t	f
12014	47	15	BASICO	318	t	f
12015	47	16	BASICO	318	t	f
12016	47	17	INTERMEDIARIO	320	t	f
12017	47	18	BASICO	318	t	f
12018	47	19	INTERMEDIARIO	320	t	f
12019	47	20	BASICO	318	t	f
12020	47	21	INTERMEDIARIO	320	t	f
12021	47	22	INTERMEDIARIO	320	t	f
12022	47	23	BASICO	318	t	f
12023	47	24	BASICO	318	t	f
12024	47	25	BASICO	318	t	f
12025	47	26	BASICO	318	t	f
12026	47	27	INTERMEDIARIO	320	t	f
12027	47	53	BASICO	318	t	f
12028	47	54	BASICO	318	t	f
12029	47	55	INTERMEDIARIO	320	t	f
12030	47	56	INTERMEDIARIO	320	t	f
12031	47	57	BASICO	318	t	f
12032	47	58	BASICO	318	t	f
12033	47	59	INTERMEDIARIO	320	t	f
12034	47	60	INTERMEDIARIO	320	t	f
12035	47	61	INTERMEDIARIO	320	t	f
12036	47	62	INTERMEDIARIO	320	t	f
12037	47	115	INTERMEDIARIO	320	t	f
12038	47	116	INTERMEDIARIO	320	t	f
12039	47	117	INTERMEDIARIO	320	t	f
12040	47	118	INTERMEDIARIO	320	t	f
12041	47	119	INTERMEDIARIO	320	t	f
12042	47	120	INTERMEDIARIO	320	t	f
12043	47	129	INTERMEDIARIO	320	t	f
12044	47	1	INTERMEDIARIO	320	t	f
12045	47	2	BASICO	318	t	f
12046	47	12	INTERMEDIARIO	320	t	f
12047	47	63	INTERMEDIARIO	320	t	f
12048	47	64	INTERMEDIARIO	320	t	f
12049	47	65	INTERMEDIARIO	320	t	f
12050	47	66	INTERMEDIARIO	320	t	f
12051	47	72	INTERMEDIARIO	320	t	f
12052	47	74	INTERMEDIARIO	320	t	f
12053	305	98	BASICO	318	t	f
12054	305	99	BASICO	318	t	f
12055	305	100	BASICO	318	t	f
12056	305	101	BASICO	318	t	f
12057	305	102	BASICO	318	t	f
12058	305	103	BASICO	318	t	f
12059	305	104	BASICO	318	t	f
12060	305	105	BASICO	318	t	f
12061	305	106	BASICO	318	t	f
12062	305	107	BASICO	318	t	f
12063	305	56	BASICO	318	t	f
12064	144	98	BASICO	318	t	f
12065	144	99	BASICO	318	t	f
12066	144	100	BASICO	318	t	f
12067	144	101	BASICO	318	t	f
12068	144	102	BASICO	318	t	f
12069	144	103	BASICO	318	t	f
12070	144	104	BASICO	318	t	f
12071	144	105	BASICO	318	t	f
12072	144	106	BASICO	318	t	f
12073	144	107	BASICO	318	t	f
12074	144	47	BASICO	318	t	f
12075	144	48	BASICO	318	t	f
12076	144	49	BASICO	318	t	f
12077	144	50	BASICO	318	t	f
12078	144	51	BASICO	318	t	f
12079	144	52	BASICO	318	t	f
12080	144	28	BASICO	318	t	f
12081	144	29	BASICO	318	t	f
12082	144	30	BASICO	318	t	f
12083	144	31	BASICO	318	t	f
12084	144	32	BASICO	318	t	f
12085	144	33	BASICO	318	t	f
12086	144	34	BASICO	318	t	f
12087	144	35	BASICO	318	t	f
12088	144	36	BASICO	318	t	f
12089	144	37	BASICO	318	t	f
12090	144	38	BASICO	318	t	f
12091	144	39	BASICO	318	t	f
12092	144	40	BASICO	318	t	f
12093	144	41	BASICO	318	t	f
12094	144	42	BASICO	318	t	f
12095	144	43	BASICO	318	t	f
12096	144	44	BASICO	318	t	f
12097	144	45	BASICO	318	t	f
12098	144	46	BASICO	318	t	f
12099	144	13	BASICO	318	t	f
12100	144	14	BASICO	318	t	f
12101	144	15	BASICO	318	t	f
12102	144	16	BASICO	318	t	f
12103	144	17	BASICO	318	t	f
12104	144	18	BASICO	318	t	f
12105	144	19	BASICO	318	t	f
12106	144	20	BASICO	318	t	f
12107	144	21	BASICO	318	t	f
12108	144	22	BASICO	318	t	f
12109	144	23	BASICO	318	t	f
12110	144	24	BASICO	318	t	f
12111	144	25	BASICO	318	t	f
12112	144	26	BASICO	318	t	f
12113	144	27	BASICO	318	t	f
12114	144	53	BASICO	318	t	f
12115	144	54	BASICO	318	t	f
12116	144	56	BASICO	318	t	f
12117	144	57	BASICO	318	t	f
12118	144	58	BASICO	318	t	f
12119	144	59	BASICO	318	t	f
12120	144	60	BASICO	318	t	f
12121	144	61	BASICO	318	t	f
12122	144	62	BASICO	318	t	f
12123	144	83	BASICO	318	t	f
12124	144	84	BASICO	318	t	f
12125	144	85	BASICO	318	t	f
12126	144	86	BASICO	318	t	f
12127	144	87	BASICO	318	t	f
12128	144	88	BASICO	318	t	f
12129	144	89	BASICO	318	t	f
12130	144	90	BASICO	318	t	f
12131	144	91	BASICO	318	t	f
12132	144	92	BASICO	318	t	f
12133	144	93	BASICO	318	t	f
12134	144	94	BASICO	318	t	f
12135	144	95	BASICO	318	t	f
12136	144	96	BASICO	318	t	f
12137	144	97	BASICO	318	t	f
12138	144	130	BASICO	318	t	f
12139	144	113	BASICO	318	t	f
12140	144	114	BASICO	318	t	f
12141	144	115	BASICO	318	t	f
12142	144	116	BASICO	318	t	f
12143	144	117	BASICO	318	t	f
12144	144	118	BASICO	318	t	f
12145	144	119	BASICO	318	t	f
12146	144	120	BASICO	318	t	f
12147	144	121	BASICO	318	t	f
12148	144	122	BASICO	318	t	f
12149	144	123	BASICO	318	t	f
12150	144	124	BASICO	318	t	f
12151	144	125	BASICO	318	t	f
12152	144	126	BASICO	318	t	f
12153	144	127	BASICO	318	t	f
12154	144	129	BASICO	318	t	f
12155	144	1	BASICO	318	t	f
12156	144	2	BASICO	318	t	f
12157	144	3	BASICO	318	t	f
12158	144	4	BASICO	318	t	f
12159	144	5	BASICO	318	t	f
12160	144	6	BASICO	318	t	f
12161	144	7	BASICO	318	t	f
12162	144	8	BASICO	318	t	f
12163	144	9	BASICO	318	t	f
12164	144	10	BASICO	318	t	f
12165	144	11	BASICO	318	t	f
12166	144	12	BASICO	318	t	f
12167	144	63	BASICO	318	t	f
12168	144	64	BASICO	318	t	f
12169	144	65	BASICO	318	t	f
12170	144	66	BASICO	318	t	f
12171	144	67	BASICO	318	t	f
12172	144	68	BASICO	318	t	f
12173	144	69	BASICO	318	t	f
12174	144	70	BASICO	318	t	f
12175	144	71	BASICO	318	t	f
12176	144	72	BASICO	318	t	f
12177	144	73	BASICO	318	t	f
12178	144	74	BASICO	318	t	f
12179	144	75	BASICO	318	t	f
12180	144	76	BASICO	318	t	f
12181	144	77	BASICO	318	t	f
12182	144	78	BASICO	318	t	f
12183	144	79	BASICO	318	t	f
12184	144	81	BASICO	318	t	f
12185	144	82	BASICO	318	t	f
12186	144	108	BASICO	318	t	f
12187	144	109	BASICO	318	t	f
12188	144	110	BASICO	318	t	f
12189	144	111	BASICO	318	t	f
12190	144	112	BASICO	318	t	f
12191	237	98	INTERMEDIARIO	320	t	f
12192	237	102	BASICO	318	t	f
12193	237	106	INTERMEDIARIO	320	t	f
12194	237	50	INTERMEDIARIO	320	t	f
12195	237	52	BASICO	318	t	f
12196	237	28	INTERMEDIARIO	320	t	f
12197	237	29	AVANCADO	321	t	f
12198	237	33	BASICO	318	t	f
12199	237	34	BASICO	318	t	f
12200	237	35	INTERMEDIARIO	320	t	f
12201	237	36	INTERMEDIARIO	320	t	f
12202	237	38	INTERMEDIARIO	320	t	f
12203	237	40	AVANCADO	321	t	f
12204	237	41	AVANCADO	321	t	f
12205	237	42	INTERMEDIARIO	320	t	f
12206	237	43	INTERMEDIARIO	320	t	f
12207	237	44	AVANCADO	321	t	f
12208	237	14	INTERMEDIARIO	320	t	f
12209	237	16	INTERMEDIARIO	320	t	f
12210	237	21	AVANCADO	321	t	f
12211	237	26	BASICO	318	t	f
12212	237	53	BASICO	318	t	f
12213	237	54	BASICO	318	t	f
12214	237	55	AVANCADO	321	t	f
12215	237	56	AVANCADO	321	t	f
12216	237	58	AVANCADO	321	t	f
12217	237	59	BASICO	318	t	f
12218	237	60	BASICO	318	t	f
12219	237	61	INTERMEDIARIO	320	t	f
12220	237	62	BASICO	318	t	f
12221	237	89	AVANCADO	321	t	f
12222	237	92	BASICO	318	t	f
12223	237	94	BASICO	318	t	f
12224	237	113	AVANCADO	321	t	f
12225	237	114	AVANCADO	321	t	f
12226	237	115	AVANCADO	321	t	f
12227	237	116	AVANCADO	321	t	f
12228	237	117	AVANCADO	321	t	f
12229	237	118	INTERMEDIARIO	320	t	f
12230	237	119	AVANCADO	321	t	f
12231	237	120	AVANCADO	321	t	f
12232	237	121	BASICO	318	t	f
12233	237	122	BASICO	318	t	f
12234	237	123	AVANCADO	321	t	f
12235	237	124	BASICO	318	t	f
12236	237	125	AVANCADO	321	t	f
12237	237	129	AVANCADO	321	t	f
12238	237	8	INTERMEDIARIO	320	t	f
12239	237	9	INTERMEDIARIO	320	t	f
12240	237	63	INTERMEDIARIO	320	t	f
12241	237	64	BASICO	318	t	f
12242	237	65	AVANCADO	321	t	f
12243	237	66	INTERMEDIARIO	320	t	f
12244	237	67	BASICO	318	t	f
12245	237	68	INTERMEDIARIO	320	t	f
12246	237	70	BASICO	318	t	f
12247	237	71	AVANCADO	321	t	f
12248	237	72	AVANCADO	321	t	f
12249	237	73	BASICO	318	t	f
12250	237	75	BASICO	318	t	f
12251	237	78	AVANCADO	321	t	f
12252	237	79	BASICO	318	t	f
12253	237	81	INTERMEDIARIO	320	t	f
12254	237	82	AVANCADO	321	t	f
12255	237	110	AVANCADO	321	t	f
12256	237	111	INTERMEDIARIO	320	t	f
12257	111	106	BASICO	318	t	f
12258	111	107	BASICO	318	t	f
12259	111	39	BASICO	318	t	f
12260	111	16	BASICO	318	t	f
12261	31	98	INTERMEDIARIO	320	t	f
12262	31	99	INTERMEDIARIO	320	t	f
12263	31	100	INTERMEDIARIO	320	t	f
12264	31	101	AVANCADO	321	t	f
12265	31	102	INTERMEDIARIO	320	t	f
12266	31	103	AVANCADO	321	t	f
12267	31	104	INTERMEDIARIO	320	t	f
12268	31	105	AVANCADO	321	t	f
12269	31	106	INTERMEDIARIO	320	t	f
12270	31	107	AVANCADO	321	t	f
12271	31	47	INTERMEDIARIO	320	t	f
12272	31	48	AVANCADO	321	t	f
12273	31	49	INTERMEDIARIO	320	t	f
12274	31	50	INTERMEDIARIO	320	t	f
12275	31	51	AVANCADO	321	t	f
12276	31	52	INTERMEDIARIO	320	t	f
12277	31	28	AVANCADO	321	t	f
12278	31	29	INTERMEDIARIO	320	t	f
12279	31	30	INTERMEDIARIO	320	t	f
12280	31	31	INTERMEDIARIO	320	t	f
12281	31	32	INTERMEDIARIO	320	t	f
12282	31	33	INTERMEDIARIO	320	t	f
12283	31	34	INTERMEDIARIO	320	t	f
12284	31	35	INTERMEDIARIO	320	t	f
12285	31	36	AVANCADO	321	t	f
12286	31	37	INTERMEDIARIO	320	t	f
12287	31	38	AVANCADO	321	t	f
12288	31	39	INTERMEDIARIO	320	t	f
12289	31	40	AVANCADO	321	t	f
12290	31	41	INTERMEDIARIO	320	t	f
12291	31	42	AVANCADO	321	t	f
12292	31	43	INTERMEDIARIO	320	t	f
12293	31	44	INTERMEDIARIO	320	t	f
12294	31	45	INTERMEDIARIO	320	t	f
12295	31	46	INTERMEDIARIO	320	t	f
12296	31	13	INTERMEDIARIO	320	t	f
12297	31	14	INTERMEDIARIO	320	t	f
12298	31	15	BASICO	318	t	f
12299	31	16	AVANCADO	321	t	f
12300	31	17	AVANCADO	321	t	f
12301	31	18	INTERMEDIARIO	320	t	f
12302	31	19	BASICO	318	t	f
12303	31	20	INTERMEDIARIO	320	t	f
12304	31	21	AVANCADO	321	t	f
12305	31	22	BASICO	318	t	f
12306	31	23	INTERMEDIARIO	320	t	f
12307	31	24	BASICO	318	t	f
12308	31	25	BASICO	318	t	f
12309	31	26	INTERMEDIARIO	320	t	f
12310	31	27	INTERMEDIARIO	320	t	f
12311	31	53	INTERMEDIARIO	320	t	f
12312	31	54	INTERMEDIARIO	320	t	f
12313	31	55	BASICO	318	t	f
12314	31	56	AVANCADO	321	t	f
12315	31	57	INTERMEDIARIO	320	t	f
12316	31	58	AVANCADO	321	t	f
12317	31	59	INTERMEDIARIO	320	t	f
12318	31	60	BASICO	318	t	f
12319	31	61	BASICO	318	t	f
12320	31	62	INTERMEDIARIO	320	t	f
12321	31	83	INTERMEDIARIO	320	t	f
12322	31	84	BASICO	318	t	f
12323	31	85	BASICO	318	t	f
12324	31	86	INTERMEDIARIO	320	t	f
12325	31	87	INTERMEDIARIO	320	t	f
12326	31	88	BASICO	318	t	f
12327	31	89	INTERMEDIARIO	320	t	f
12328	31	90	BASICO	318	t	f
12329	31	91	INTERMEDIARIO	320	t	f
12330	31	92	BASICO	318	t	f
12331	31	93	BASICO	318	t	f
12332	31	94	INTERMEDIARIO	320	t	f
12333	31	96	INTERMEDIARIO	320	t	f
12334	31	97	INTERMEDIARIO	320	t	f
12335	31	130	BASICO	318	t	f
12336	31	113	INTERMEDIARIO	320	t	f
12337	31	114	INTERMEDIARIO	320	t	f
12338	31	115	BASICO	318	t	f
12339	31	116	BASICO	318	t	f
12340	31	117	BASICO	318	t	f
12341	31	118	INTERMEDIARIO	320	t	f
12342	31	119	INTERMEDIARIO	320	t	f
12343	31	125	INTERMEDIARIO	320	t	f
12344	31	126	INTERMEDIARIO	320	t	f
12345	31	127	BASICO	318	t	f
12346	31	129	BASICO	318	t	f
12347	31	1	BASICO	318	t	f
12348	31	2	BASICO	318	t	f
12349	31	3	INTERMEDIARIO	320	t	f
12350	31	4	BASICO	318	t	f
12351	31	5	BASICO	318	t	f
12352	31	6	INTERMEDIARIO	320	t	f
12353	31	7	INTERMEDIARIO	320	t	f
12354	31	8	INTERMEDIARIO	320	t	f
12355	31	9	INTERMEDIARIO	320	t	f
12356	31	10	INTERMEDIARIO	320	t	f
12357	31	11	BASICO	318	t	f
12358	31	12	INTERMEDIARIO	320	t	f
12359	31	63	INTERMEDIARIO	320	t	f
12360	31	64	BASICO	318	t	f
12361	31	65	INTERMEDIARIO	320	t	f
12362	31	66	BASICO	318	t	f
12363	31	67	INTERMEDIARIO	320	t	f
12364	31	68	BASICO	318	t	f
12365	31	69	BASICO	318	t	f
12366	31	70	BASICO	318	t	f
12367	31	71	BASICO	318	t	f
12368	31	72	INTERMEDIARIO	320	t	f
12369	31	73	INTERMEDIARIO	320	t	f
12370	31	74	BASICO	318	t	f
12371	31	75	BASICO	318	t	f
12372	31	76	INTERMEDIARIO	320	t	f
12373	31	77	INTERMEDIARIO	320	t	f
12374	31	78	BASICO	318	t	f
12375	31	79	BASICO	318	t	f
12376	31	81	INTERMEDIARIO	320	t	f
12377	31	82	BASICO	318	t	f
12378	31	108	BASICO	318	t	f
12379	31	109	BASICO	318	t	f
12380	31	110	BASICO	318	t	f
12381	31	111	BASICO	318	t	f
12382	31	112	BASICO	318	t	f
12383	140	98	BASICO	318	t	f
12384	140	99	BASICO	318	t	f
12385	140	100	BASICO	318	t	f
12386	140	101	BASICO	318	t	f
12387	140	102	BASICO	318	t	f
12388	140	103	BASICO	318	t	f
12389	140	104	BASICO	318	t	f
12390	140	105	BASICO	318	t	f
12391	140	106	BASICO	318	t	f
12392	140	107	INTERMEDIARIO	320	t	f
12393	140	47	BASICO	318	t	f
12394	140	48	BASICO	318	t	f
12395	140	49	BASICO	318	t	f
12396	140	50	INTERMEDIARIO	320	t	f
12397	140	51	BASICO	318	t	f
12398	140	52	INTERMEDIARIO	320	t	f
12399	140	28	BASICO	318	t	f
12400	140	29	BASICO	318	t	f
12401	140	30	INTERMEDIARIO	320	t	f
12402	140	31	BASICO	318	t	f
12403	140	32	BASICO	318	t	f
12404	140	33	BASICO	318	t	f
12405	140	34	INTERMEDIARIO	320	t	f
12406	140	35	INTERMEDIARIO	320	t	f
12407	140	36	INTERMEDIARIO	320	t	f
12408	140	37	INTERMEDIARIO	320	t	f
12409	140	38	INTERMEDIARIO	320	t	f
12410	140	39	BASICO	318	t	f
12411	140	40	BASICO	318	t	f
12412	140	41	INTERMEDIARIO	320	t	f
12413	140	42	BASICO	318	t	f
12414	140	43	INTERMEDIARIO	320	t	f
12415	140	44	BASICO	318	t	f
12416	140	45	BASICO	318	t	f
12417	140	46	BASICO	318	t	f
12418	140	13	BASICO	318	t	f
12419	140	15	BASICO	318	t	f
12420	140	16	INTERMEDIARIO	320	t	f
12421	140	17	INTERMEDIARIO	320	t	f
12422	140	18	BASICO	318	t	f
12423	140	19	BASICO	318	t	f
12424	140	20	BASICO	318	t	f
12425	140	22	INTERMEDIARIO	320	t	f
12426	140	23	BASICO	318	t	f
12427	140	24	BASICO	318	t	f
12428	140	25	BASICO	318	t	f
12429	140	26	INTERMEDIARIO	320	t	f
12430	140	27	BASICO	318	t	f
12431	140	53	INTERMEDIARIO	320	t	f
12432	140	54	BASICO	318	t	f
12433	140	55	INTERMEDIARIO	320	t	f
12434	140	56	INTERMEDIARIO	320	t	f
12435	140	57	BASICO	318	t	f
12436	140	58	INTERMEDIARIO	320	t	f
12437	140	59	INTERMEDIARIO	320	t	f
12438	140	60	INTERMEDIARIO	320	t	f
12439	140	61	INTERMEDIARIO	320	t	f
12440	140	62	BASICO	318	t	f
12441	140	83	BASICO	318	t	f
12442	140	84	BASICO	318	t	f
12443	140	85	INTERMEDIARIO	320	t	f
12444	140	86	BASICO	318	t	f
12445	140	87	BASICO	318	t	f
12446	140	88	BASICO	318	t	f
12447	140	89	BASICO	318	t	f
12448	140	90	BASICO	318	t	f
12449	140	91	BASICO	318	t	f
12450	140	92	BASICO	318	t	f
12451	140	93	BASICO	318	t	f
12452	140	94	BASICO	318	t	f
12453	140	95	BASICO	318	t	f
12454	140	96	BASICO	318	t	f
12455	140	97	BASICO	318	t	f
12456	140	130	BASICO	318	t	f
12457	140	113	AVANCADO	321	t	f
12458	140	114	INTERMEDIARIO	320	t	f
12459	140	115	INTERMEDIARIO	320	t	f
12460	140	116	INTERMEDIARIO	320	t	f
12461	140	117	INTERMEDIARIO	320	t	f
12462	140	118	INTERMEDIARIO	320	t	f
12463	140	119	INTERMEDIARIO	320	t	f
12464	140	120	INTERMEDIARIO	320	t	f
12465	140	121	BASICO	318	t	f
12466	140	122	BASICO	318	t	f
12467	140	123	INTERMEDIARIO	320	t	f
12468	140	124	BASICO	318	t	f
12469	140	125	BASICO	318	t	f
12470	140	126	BASICO	318	t	f
12471	140	127	BASICO	318	t	f
12472	140	129	AVANCADO	321	t	f
12473	140	1	INTERMEDIARIO	320	t	f
12474	140	3	BASICO	318	t	f
12475	140	4	INTERMEDIARIO	320	t	f
12476	140	5	BASICO	318	t	f
12477	140	6	BASICO	318	t	f
12478	140	7	BASICO	318	t	f
12479	140	8	BASICO	318	t	f
12480	140	9	BASICO	318	t	f
12481	140	10	INTERMEDIARIO	320	t	f
12482	140	11	BASICO	318	t	f
12483	140	12	INTERMEDIARIO	320	t	f
12484	140	63	INTERMEDIARIO	320	t	f
12485	140	64	INTERMEDIARIO	320	t	f
12486	140	65	AVANCADO	321	t	f
12487	140	66	INTERMEDIARIO	320	t	f
12488	140	67	INTERMEDIARIO	320	t	f
12489	140	68	BASICO	318	t	f
12490	140	69	BASICO	318	t	f
12491	140	70	BASICO	318	t	f
12492	140	71	INTERMEDIARIO	320	t	f
12493	140	72	AVANCADO	321	t	f
12494	140	73	BASICO	318	t	f
12495	140	74	BASICO	318	t	f
12496	140	75	BASICO	318	t	f
12497	140	76	BASICO	318	t	f
12498	140	77	BASICO	318	t	f
12499	140	78	BASICO	318	t	f
12500	140	79	BASICO	318	t	f
12501	140	81	BASICO	318	t	f
12502	140	82	AVANCADO	321	t	f
12503	140	108	INTERMEDIARIO	320	t	f
12504	140	109	INTERMEDIARIO	320	t	f
12505	140	110	INTERMEDIARIO	320	t	f
12506	140	111	INTERMEDIARIO	320	t	f
12507	140	112	INTERMEDIARIO	320	t	f
12508	42	98	BASICO	318	t	f
12509	42	99	BASICO	318	t	f
12510	42	100	BASICO	318	t	f
12511	42	101	BASICO	318	t	f
12512	42	103	INTERMEDIARIO	320	t	f
12513	42	104	BASICO	318	t	f
12514	42	105	INTERMEDIARIO	320	t	f
12515	42	106	INTERMEDIARIO	320	t	f
12516	42	107	BASICO	318	t	f
12517	42	47	BASICO	318	t	f
12518	42	48	BASICO	318	t	f
12519	42	49	BASICO	318	t	f
12520	42	50	BASICO	318	t	f
12521	42	51	BASICO	318	t	f
12522	42	52	BASICO	318	t	f
12523	42	28	BASICO	318	t	f
12524	42	29	INTERMEDIARIO	320	t	f
12525	42	30	BASICO	318	t	f
12526	42	31	BASICO	318	t	f
12527	42	32	BASICO	318	t	f
12528	42	33	INTERMEDIARIO	320	t	f
12529	42	34	INTERMEDIARIO	320	t	f
12530	42	35	BASICO	318	t	f
12531	42	36	INTERMEDIARIO	320	t	f
12532	42	37	BASICO	318	t	f
12533	42	38	BASICO	318	t	f
12534	42	39	BASICO	318	t	f
12535	42	40	INTERMEDIARIO	320	t	f
12536	42	41	INTERMEDIARIO	320	t	f
12537	42	42	BASICO	318	t	f
12538	42	43	BASICO	318	t	f
12539	42	44	INTERMEDIARIO	320	t	f
12540	42	45	BASICO	318	t	f
12541	42	46	BASICO	318	t	f
12542	42	13	BASICO	318	t	f
12543	42	14	BASICO	318	t	f
12544	42	15	BASICO	318	t	f
12545	42	16	BASICO	318	t	f
12546	42	17	BASICO	318	t	f
12547	42	18	BASICO	318	t	f
12548	42	19	BASICO	318	t	f
12549	42	20	BASICO	318	t	f
12550	42	21	BASICO	318	t	f
12551	42	22	BASICO	318	t	f
12552	42	23	BASICO	318	t	f
12553	42	24	BASICO	318	t	f
12554	42	25	BASICO	318	t	f
12555	42	26	BASICO	318	t	f
12556	42	27	BASICO	318	t	f
12557	42	53	BASICO	318	t	f
12558	42	54	BASICO	318	t	f
12559	42	55	BASICO	318	t	f
12560	42	56	BASICO	318	t	f
12561	42	57	BASICO	318	t	f
12562	42	58	BASICO	318	t	f
12563	42	59	BASICO	318	t	f
12564	42	60	BASICO	318	t	f
12565	42	61	BASICO	318	t	f
12566	42	62	BASICO	318	t	f
12567	42	83	BASICO	318	t	f
12568	42	84	BASICO	318	t	f
12569	42	85	BASICO	318	t	f
12570	42	86	BASICO	318	t	f
12571	42	87	BASICO	318	t	f
12572	42	88	BASICO	318	t	f
12573	42	89	BASICO	318	t	f
12574	42	90	BASICO	318	t	f
12575	42	91	BASICO	318	t	f
12576	42	92	BASICO	318	t	f
12577	42	93	BASICO	318	t	f
12578	42	94	BASICO	318	t	f
12579	42	95	BASICO	318	t	f
12580	42	96	BASICO	318	t	f
12581	42	97	BASICO	318	t	f
12582	42	130	BASICO	318	t	f
12583	42	113	BASICO	318	t	f
12584	42	114	BASICO	318	t	f
12585	42	115	BASICO	318	t	f
12586	42	116	BASICO	318	t	f
12587	42	117	BASICO	318	t	f
12588	42	118	BASICO	318	t	f
12589	42	119	BASICO	318	t	f
12590	42	120	BASICO	318	t	f
12591	42	121	BASICO	318	t	f
12592	42	122	BASICO	318	t	f
12593	42	123	BASICO	318	t	f
12594	42	124	INTERMEDIARIO	320	t	f
12595	42	125	BASICO	318	t	f
12596	42	126	BASICO	318	t	f
12597	42	127	BASICO	318	t	f
12598	42	129	INTERMEDIARIO	320	t	f
12599	42	1	BASICO	318	t	f
12600	42	2	BASICO	318	t	f
12601	42	3	BASICO	318	t	f
12602	42	4	BASICO	318	t	f
12603	42	5	BASICO	318	t	f
12604	42	6	BASICO	318	t	f
12605	42	7	BASICO	318	t	f
12606	42	8	BASICO	318	t	f
12607	42	9	BASICO	318	t	f
12608	42	10	BASICO	318	t	f
12609	42	11	BASICO	318	t	f
12610	42	12	BASICO	318	t	f
12611	42	63	INTERMEDIARIO	320	t	f
12612	42	64	BASICO	318	t	f
12613	42	65	BASICO	318	t	f
12614	42	66	INTERMEDIARIO	320	t	f
12615	42	67	BASICO	318	t	f
12616	42	68	BASICO	318	t	f
12617	42	69	BASICO	318	t	f
12618	42	70	BASICO	318	t	f
12619	42	71	BASICO	318	t	f
12620	42	72	AVANCADO	321	t	f
12621	42	73	INTERMEDIARIO	320	t	f
12622	42	74	BASICO	318	t	f
12623	42	75	INTERMEDIARIO	320	t	f
12624	42	76	INTERMEDIARIO	320	t	f
12625	42	77	AVANCADO	321	t	f
12626	42	78	BASICO	318	t	f
12627	42	79	BASICO	318	t	f
12628	42	81	BASICO	318	t	f
12629	42	82	AVANCADO	321	t	f
12630	42	108	BASICO	318	t	f
12631	42	109	BASICO	318	t	f
12632	42	110	BASICO	318	t	f
12633	42	111	BASICO	318	t	f
12634	42	112	BASICO	318	t	f
12635	63	36	BASICO	318	t	f
12636	63	16	BASICO	318	t	f
12637	63	20	BASICO	318	t	f
12638	63	21	BASICO	318	t	f
12639	63	55	BASICO	318	t	f
12640	63	56	BASICO	318	t	f
12641	63	58	BASICO	318	t	f
12642	63	12	BASICO	318	t	f
12643	63	72	BASICO	318	t	f
12644	63	82	BASICO	318	t	f
12645	104	41	INTERMEDIARIO	320	t	f
12646	104	50	INTERMEDIARIO	320	t	f
12647	104	65	INTERMEDIARIO	320	t	f
12648	111	139	INTERMEDIARIO	320	t	f
12649	137	139	INTERMEDIARIO	320	t	f
12650	233	139	INTERMEDIARIO	320	t	f
12651	42	139	INTERMEDIARIO	320	t	f
12652	197	139	INTERMEDIARIO	320	t	f
12653	37	139	INTERMEDIARIO	320	t	f
12654	156	139	INTERMEDIARIO	320	t	f
12655	333	139	INTERMEDIARIO	320	t	f
12656	225	146	INTERMEDIARIO	320	t	f
12657	197	146	INTERMEDIARIO	320	t	f
12658	272	146	INTERMEDIARIO	320	t	f
12659	125	146	INTERMEDIARIO	320	t	f
12660	54	146	INTERMEDIARIO	320	t	f
12661	46	146	INTERMEDIARIO	320	t	f
12662	45	146	INTERMEDIARIO	320	t	f
12663	332	146	INTERMEDIARIO	320	t	f
12664	335	156	INTERMEDIARIO	320	t	f
12665	208	156	INTERMEDIARIO	320	t	f
12666	42	156	INTERMEDIARIO	320	t	f
12667	81	156	INTERMEDIARIO	320	t	f
12668	94	156	INTERMEDIARIO	320	t	f
12669	297	156	INTERMEDIARIO	320	t	f
12670	32	156	INTERMEDIARIO	320	t	f
12671	213	156	INTERMEDIARIO	320	t	f
12672	259	157	INTERMEDIARIO	320	t	f
12673	102	157	INTERMEDIARIO	320	t	f
12674	114	157	INTERMEDIARIO	320	t	f
12675	11	157	INTERMEDIARIO	320	t	f
12676	174	157	INTERMEDIARIO	320	t	f
12677	113	157	INTERMEDIARIO	320	t	f
12678	92	157	INTERMEDIARIO	320	t	f
12679	95	157	INTERMEDIARIO	320	t	f
\.


--
-- TOC entry 3625 (class 0 OID 95655)
-- Dependencies: 227
-- Data for Name: colaboradores; Type: TABLE DATA; Schema: InHire; Owner: postgres
--

COPY "InHire".colaboradores (id, nome_abreviado, data_admissao, id_cargo, id_senioridade, id_step, id_vinculo, id_modalidade, id_setor_empresa, id_contrato, status, deletado) FROM stdin;
1	Aaron Freire Mocado	2025-07-21 00:00:00+00	121	153	158	141	147	297	6	t	f
2	Abilene Damasceno Mocado	2023-05-15 00:00:00+00	91	155	158	141	148	297	\N	t	f
3	Adrias Souza Mocado	2025-05-05 00:00:00+00	121	139	158	141	147	297	8	t	f
4	Alairton Silva Mocado	2024-03-06 00:00:00+00	97	155	158	141	147	297	6	t	f
5	Alancardek Ferraz Mocado	2018-09-05 00:00:00+00	97	155	158	141	147	297	8	t	f
6	Alex Menezes Mocado	2020-10-05 00:00:00+00	97	155	158	141	147	297	8	t	f
7	Amarildo Carvalho Mocado	2025-03-06 00:00:00+00	135	153	158	141	147	297	4	t	f
9	Ana Soares Mocado	2025-01-21 00:00:00+00	138	155	158	141	147	297	6	t	f
10	Ana Gomes Mocado	2024-11-01 00:00:00+00	139	152	158	141	147	297	4	t	f
11	Ana Pinheiro Mocado	2023-08-18 00:00:00+00	93	154	158	141	147	297	4	t	f
14	Anatalimar Lemos Mocado	2025-02-03 00:00:00+00	97	153	158	141	147	297	4	t	f
15	Anderson Ferreira Mocado	2024-02-06 00:00:00+00	121	154	158	141	147	297	7	t	f
16	Andre Menezes Mocado	2019-07-16 00:00:00+00	100	153	158	141	147	297	4	t	f
17	Andremar Ramos Mocado	2021-10-20 00:00:00+00	121	154	158	142	148	297	4	t	f
18	Andrey Ribeiro Mocado	2018-09-04 00:00:00+00	93	155	158	141	148	297	8	t	f
19	Antonio Pereira Mocado	2025-11-24 00:00:00+00	93	153	158	141	148	297	\N	f	f
20	Aristezio Junior Mocado	2024-04-01 00:00:00+00	121	155	158	141	148	297	\N	t	f
21	Aryberg Duarte Mocado	2021-11-03 00:00:00+00	93	153	158	141	148	297	\N	f	f
22	Beatriz Sena Mocado	2024-04-15 00:00:00+00	135	155	158	141	147	297	6	t	f
23	Bento Bandeira Mocado	2026-01-19 00:00:00+00	79	153	161	141	147	297	\N	t	f
24	Bianca Mourao Mocado	2023-06-01 00:00:00+00	135	153	158	141	147	297	8	t	f
27	Bruno Moreira Mocado	2023-01-11 00:00:00+00	76	153	158	141	147	297	\N	t	f
28	Bruno Santos Mocado	2018-09-04 00:00:00+00	97	154	158	141	147	297	8	t	f
29	Caio Machado Mocado	2024-10-07 00:00:00+00	89	153	158	141	148	297	\N	f	f
30	Camila Silva Mocado	2024-01-15 00:00:00+00	96	154	160	141	148	297	\N	t	f
31	Carla Rocha Mocado	2023-09-11 00:00:00+00	93	154	158	141	147	297	4	t	f
32	Carlos Farias Mocado	2024-02-19 00:00:00+00	114	153	158	141	147	297	6	t	f
33	Carlos Souza Mocado	2023-06-01 00:00:00+00	123	155	158	141	147	297	7	t	f
34	Catherine Afonso Mocado	2024-05-20 00:00:00+00	91	153	158	141	147	297	7	t	f
35	Celso Albuquerque Mocado	2018-09-17 00:00:00+00	93	156	158	141	148	297	8	t	f
36	César Ferreira Mocado	2023-08-18 00:00:00+00	93	153	158	141	148	297	\N	f	f
37	Christian Paes Mocado	2024-03-06 00:00:00+00	97	155	158	141	147	297	6	t	f
38	Claudia Hossaine Mocado	2023-08-23 00:00:00+00	93	154	158	141	147	297	4	t	f
40	Daniel Falcao Mocado	2023-07-03 00:00:00+00	93	155	158	141	148	297	\N	f	f
41	Daniel Brandão Mocado	2023-12-18 00:00:00+00	93	154	158	141	148	297	\N	f	f
42	Daniel Santos Mocado	2023-08-18 00:00:00+00	93	153	158	141	147	297	4	t	f
43	Daniela Sales Mocado	2024-10-07 00:00:00+00	93	153	158	141	147	297	\N	f	f
44	Davi Queiroz Mocado	2024-02-21 00:00:00+00	138	153	158	141	147	297	6	f	f
45	David Cardoso Mocado	2024-03-06 00:00:00+00	97	155	158	141	147	297	6	t	f
46	Demis Rocha Mocado	2018-09-04 00:00:00+00	97	155	158	141	147	297	8	t	f
47	Diego Sousa Mocado	2023-08-18 00:00:00+00	121	153	158	141	147	297	4	t	f
48	Dimitris Calixto Mocado	2025-04-01 00:00:00+00	93	153	158	141	147	297	8	t	f
49	Diogo Cordeiro Mocado	2024-07-15 00:00:00+00	93	153	158	141	147	297	8	t	f
50	Dorival Melo Mocado	2023-08-18 00:00:00+00	135	153	158	141	147	297	4	t	f
51	Eduardo Barbosa Mocado	2023-08-18 00:00:00+00	93	153	158	141	147	297	4	t	f
52	Eduardo Pereira Mocado	2024-02-19 00:00:00+00	79	153	158	141	147	297	\N	f	f
53	Eduardo Noji Mocado	2025-02-17 00:00:00+00	122	155	158	141	147	297	4	t	f
54	Elinaldo Almeida Mocado	2023-08-18 00:00:00+00	135	153	158	141	147	297	4	t	f
55	Elissandra Santos Mocado	2023-06-01 00:00:00+00	138	153	158	141	147	297	7	t	f
59	Ernani Junior Mocado	2023-06-01 00:00:00+00	97	154	158	141	147	297	8	t	f
60	Evandro Nascimento Mocado	2025-09-15 00:00:00+00	135	153	158	141	148	297	4	t	f
61	Fabio Belmont Mocado	2022-03-01 00:00:00+00	91	154	158	141	148	297	14	t	f
62	Fabrício Altoé Mocado	2024-05-02 00:00:00+00	91	155	158	141	148	297	\N	f	f
63	Fabricio Nogueira Mocado	2023-08-18 00:00:00+00	135	153	158	141	147	297	4	t	f
66	Francisco Oliveira Mocado	2024-05-02 00:00:00+00	78	154	159	141	148	297	\N	t	f
68	Francisco Filho Mocado	2024-03-11 03:00:00+00	91	155	160	141	148	297	\N	t	f
69	Gabriel Pinto Mocado	2024-02-19 00:00:00+00	121	154	158	141	147	297	6	t	f
70	Gabriel Albuquerque Mocado	2021-10-20 00:00:00+00	93	153	158	141	148	297	4	t	f
71	Gabrielly Aguiar Mocado	2023-06-01 00:00:00+00	121	154	158	141	147	297	7	t	f
72	Genario Junior Mocado	2021-01-04 00:00:00+00	93	155	158	141	148	297	14	t	f
73	Gerdeson Souto Mocado	2024-09-03 00:00:00+00	139	152	158	141	148	297	\N	f	f
74	Gessyca Santos Mocado	2025-04-03 00:00:00+00	139	152	158	141	148	297	14	t	f
75	Gigliane Costa Mocado	2023-12-11 00:00:00+00	119	153	158	141	147	297	7	t	f
76	Gilmar Silva Mocado	2021-12-15 00:00:00+00	91	155	158	141	148	297	8	t	f
77	Giovanna Correia Mocado	2025-08-25 00:00:00+00	139	152	158	141	148	297	8	t	f
78	Glenda Angelim Mocado	2025-01-20 00:00:00+00	138	153	158	141	147	297	\N	f	f
79	Goncalo Duarte Mocado	2019-04-16 00:00:00+00	112	153	158	141	147	297	8	t	f
80	Gregori Souza Mocado	2020-10-23 00:00:00+00	97	155	158	141	148	297	8	t	f
81	Guilbert Carvalho Mocado	2021-11-05 00:00:00+00	93	153	158	141	147	297	8	t	f
82	Guilherme Magrego Mocado	2025-09-01 00:00:00+00	135	153	158	141	147	297	4	t	f
83	Guilherme Freire Mocado	2025-04-03 00:00:00+00	139	152	158	141	148	297	14	t	f
84	Haroldo Oliveira Mocado	2023-04-03 00:00:00+00	139	152	158	141	147	297	\N	t	f
85	Helder Silva Mocado	2024-08-01 00:00:00+00	135	153	158	141	147	297	8	t	f
86	Ido Silva Mocado	2025-03-13 00:00:00+00	139	152	158	141	148	297	14	t	f
87	Igor Maciel Mocado	2022-10-05 00:00:00+00	116	153	158	141	148	297	14	t	f
88	Igor Massulo Mocado	2024-03-06 00:00:00+00	138	155	158	141	147	297	6	t	f
90	Igor Souza Mocado	2025-04-10 00:00:00+00	97	154	158	141	148	297	8	t	f
92	Ilquias Filho Mocado	2023-06-01 00:00:00+00	137	153	158	141	148	297	7	t	f
93	Irapuan Junior Mocado	2023-11-06 00:00:00+00	93	153	158	141	148	297	14	t	f
94	Isaac Batista Mocado	2024-01-15 00:00:00+00	116	155	158	141	148	297	\N	t	f
95	Isaias Oliveira Mocado	2024-09-02 00:00:00+00	138	153	158	141	147	297	7	t	f
96	Israel Costa Mocado	2025-10-22 00:00:00+00	95	154	159	141	148	297	\N	f	f
97	Italo Almeida Mocado	2024-10-02 00:00:00+00	121	155	158	141	148	297	\N	t	f
98	Ivaney Ramos Mocado	2024-04-01 00:00:00+00	135	155	158	141	147	297	6	t	f
99	Izabella Carvalho Mocado	2026-01-05 00:00:00+00	97	155	158	141	147	297	6	t	f
100	Jamile Thomaz Mocado	2024-02-22 00:00:00+00	121	153	158	141	147	297	7	t	f
101	Janaina Araujo Mocado	2021-11-05 00:00:00+00	93	153	158	141	147	297	\N	f	f
102	Janderson Araujo Mocado	2025-06-02 00:00:00+00	138	153	158	141	147	297	8	t	f
103	Janeo Nascimento Mocado	2023-06-01 00:00:00+00	90	155	158	141	147	297	8	t	f
104	Jarbson Ferreira Mocado	2025-07-01 00:00:00+00	139	152	161	141	147	297	\N	t	f
105	Jardane Maciel Mocado	2023-06-01 00:00:00+00	137	153	158	141	147	297	\N	f	f
106	Jeferson Oliveira Mocado	2024-07-03 00:00:00+00	89	153	158	141	148	297	\N	f	f
107	Jefferson Oliveira Mocado	2025-03-10 00:00:00+00	138	153	158	141	147	297	8	t	f
108	Jessica Albuquerque Mocado	2023-06-01 00:00:00+00	88	154	158	141	147	297	8	t	f
110	Jessica Santos Mocado	2022-09-01 00:00:00+00	89	154	162	141	148	297	\N	t	f
111	Joabe Silva Mocado	2023-08-18 00:00:00+00	93	153	158	141	147	297	4	t	f
113	Joellytton Santos Mocado	2022-01-24 00:00:00+00	93	155	158	141	147	297	8	t	f
114	Jonas Sousa Mocado	2021-11-05 00:00:00+00	139	152	158	141	148	297	\N	t	f
117	José Alves Mocado	2026-02-10 00:00:00+00	135	153	158	141	147	297	5	t	f
118	José Justa Mocado	2018-09-10 00:00:00+00	93	155	158	141	147	297	8	f	f
119	José Vasconcelos Mocado	2021-04-26 00:00:00+00	116	153	158	141	148	297	\N	t	f
120	José Nascimento Mocado	2024-03-21 00:00:00+00	121	154	158	141	148	297	\N	f	f
122	José Filho Mocado	2023-11-20 00:00:00+00	121	155	158	141	148	297	\N	t	f
123	Juan Coelho Mocado	2024-01-02 00:00:00+00	121	154	158	141	147	297	7	t	f
124	Júlia Muniz Mocado	2023-10-18 00:00:00+00	140	154	158	141	148	297	\N	t	f
125	Julie Pantoja Mocado	2023-08-18 00:00:00+00	93	155	158	141	148	297	4	t	f
126	Julio Caxias Mocado	2023-08-18 00:00:00+00	93	154	158	141	147	297	4	t	f
127	Jussara Cavalcante Mocado	2025-04-01 00:00:00+00	88	155	158	141	147	297	6	t	f
128	Karine Sousa Mocado	2025-01-13 00:00:00+00	96	154	159	141	148	297	\N	t	f
129	Karla Silva Mocado	2022-03-16 00:00:00+00	94	154	158	141	147	297	\N	t	f
130	Kauan Pereira Mocado	2024-11-11 00:00:00+00	139	152	158	141	147	297	\N	t	f
131	Kleyber Araujo Mocado	2022-07-01 00:00:00+00	94	154	158	141	148	297	14	t	f
132	Lais Benezar Mocado	2024-04-15 00:00:00+00	135	155	158	141	148	297	6	t	f
133	Lara Souza Mocado	2023-08-21 00:00:00+00	135	153	158	141	147	297	4	t	f
134	Larissa Freire Mocado	2024-03-06 00:00:00+00	114	155	158	141	147	297	6	t	f
135	Larissa Dantas Mocado	2023-06-01 00:00:00+00	93	153	158	141	148	297	14	t	f
136	Leandro Lima Mocado	2021-12-01 00:00:00+00	89	153	158	141	148	297	\N	f	f
137	Leodercio Filho Mocado	2023-02-01 00:00:00+00	129	155	161	141	147	297	\N	t	f
138	Leonardo Nascimento Mocado	2021-10-04 00:00:00+00	93	154	158	141	147	297	8	t	f
140	Levi Teixeira Mocado	2025-09-01 00:00:00+00	135	153	158	141	148	297	4	t	f
142	Liliane Arrais Mocado	2025-03-10 00:00:00+00	128	151	158	141	148	297	\N	f	f
143	Luan Oliveira Mocado	2023-08-18 00:00:00+00	93	153	158	141	147	297	4	t	f
144	Lucas Nunes Mocado	2023-08-18 00:00:00+00	135	153	158	141	147	297	4	t	f
145	Lucas Menezes Mocado	2023-06-01 00:00:00+00	97	154	158	141	147	297	8	t	f
146	Lucas Scarelli Mocado	2023-11-01 00:00:00+00	138	153	158	141	147	297	\N	f	f
147	Lucas Andrade Mocado	2025-03-10 00:00:00+00	135	153	158	141	147	297	8	t	f
148	Lucas Souza Mocado	2021-09-20 00:00:00+00	121	154	158	141	147	297	4	t	f
149	Lucenildo Silva Mocado	2023-09-13 00:00:00+00	86	153	158	141	147	297	7	t	f
150	Lucilo Neto Mocado	2019-05-22 00:00:00+00	93	155	158	141	148	297	8	t	f
151	Luiz Sales Mocado	2023-07-12 00:00:00+00	97	154	158	141	147	297	8	t	f
152	Luiz Silva Mocado	2024-03-22 00:00:00+00	135	155	158	141	147	297	6	t	f
153	Luiz Silva Mocado	2023-06-01 00:00:00+00	135	153	158	141	147	297	8	t	f
154	Luiz Vieira Mocado	2025-11-17 00:00:00+00	138	155	158	141	147	297	6	t	f
155	Luiz Souza Mocado	2025-03-20 00:00:00+00	108	153	158	141	147	297	\N	f	f
156	Luiz Voss Mocado	2024-03-06 00:00:00+00	97	155	158	141	147	297	6	t	f
158	Marcio Constantino Mocado	2018-10-08 00:00:00+00	93	155	158	141	147	297	8	t	f
159	Marcos Junior Mocado	2022-12-01 00:00:00+00	94	153	158	141	148	297	\N	t	f
160	Marcos Ramos Mocado	2023-08-18 00:00:00+00	121	153	158	141	148	297	4	t	f
162	Marcos Barros Mocado	2023-06-01 00:00:00+00	138	153	158	141	147	297	\N	f	f
163	Marcos Sousa Mocado	2023-11-07 00:00:00+00	96	153	158	141	148	297	\N	t	f
167	Mariana Almeida Mocado	2024-06-03 00:00:00+00	86	153	158	141	147	297	7	t	f
168	Maryka Mendes Mocado	2025-02-11 00:00:00+00	86	154	158	141	147	297	4	t	f
169	Matheus Araujo Mocado	2024-08-22 00:00:00+00	140	154	158	141	147	297	7	t	f
170	Matheus Santos Mocado	2021-03-24 00:00:00+00	93	154	158	141	147	297	8	t	f
171	Matheus Souza Mocado	2021-02-10 00:00:00+00	93	154	158	141	148	297	8	t	f
172	Matheus Cavalcanti Mocado	2024-09-03 00:00:00+00	93	152	158	141	148	297	\N	f	f
173	Matheus Magalhaes Mocado	2023-01-16 00:00:00+00	93	153	158	141	147	297	8	t	f
174	Max Junior Mocado	2024-03-01 00:00:00+00	139	152	158	141	147	297	4	t	f
177	Moises Ribeiro Mocado	2024-02-19 00:00:00+00	138	155	158	141	147	297	6	t	f
179	Monica Veiga Mocado	2024-08-01 00:00:00+00	92	155	158	141	148	297	8	t	f
181	Nara Albuquerque Mocado	2021-11-05 00:00:00+00	138	153	158	141	147	297	8	t	f
182	Natália Araújo Mocado	2024-02-19 00:00:00+00	96	154	159	141	148	297	\N	t	f
183	Natanael Leao Mocado	2024-03-06 00:00:00+00	121	153	158	141	147	297	6	t	f
185	Nayara Dourado Mocado	2024-07-01 00:00:00+00	136	153	158	141	148	297	\N	f	f
188	Paulo Santos Mocado	2024-07-15 00:00:00+00	140	154	160	141	148	297	\N	t	f
190	Paulo Lira Mocado	2021-07-01 00:00:00+00	138	153	158	141	147	297	8	t	f
191	Pedro Silva Mocado	2022-01-11 00:00:00+00	93	153	158	141	147	297	4	t	f
194	Plinio Matos Mocado	2021-09-15 00:00:00+00	93	154	161	141	148	297	\N	t	f
196	Rafael Castro Mocado	2024-02-01 00:00:00+00	92	155	158	141	147	297	8	t	f
197	Rafael Barbosa Mocado	2023-06-01 00:00:00+00	83	154	158	141	147	297	7	t	f
198	Rafael Pires Mocado	2024-04-01 00:00:00+00	91	155	160	141	149	297	\N	t	f
199	Raoni Segal Mocado	2025-03-13 00:00:00+00	93	153	158	141	148	297	14	t	f
200	Raquel Goncalves Mocado	2024-03-06 00:00:00+00	138	155	158	141	147	297	6	t	f
202	Rejane Amorim Mocado	2019-07-04 00:00:00+00	116	155	158	141	147	297	4	t	f
203	Rhaniel Monteiro Mocado	2023-08-18 00:00:00+00	93	153	158	141	147	297	4	t	f
205	Rodrigo Nascimento Mocado	2024-03-06 00:00:00+00	138	155	158	141	147	297	6	t	f
207	Rubean Santos Mocado	2021-06-14 00:00:00+00	93	155	158	141	148	297	14	t	f
208	Sabrina Topel Mocado	2023-08-14 00:00:00+00	93	154	158	141	148	297	14	t	f
209	Said Mendonca Mocado	2025-07-16 00:00:00+00	121	154	158	141	147	297	6	t	f
210	Samuel Feijo Mocado	2024-02-19 00:00:00+00	121	154	158	141	147	297	7	t	f
211	Sander Costa Mocado	2023-06-01 00:00:00+00	97	154	158	141	147	297	8	t	f
212	Siwan Filho Mocado	2026-01-07 00:00:00+00	93	154	158	141	147	297	\N	t	f
213	Socrates Paiva Mocado	2020-10-05 00:00:00+00	97	155	158	141	147	297	8	t	f
214	Sonia Gonzaga Mocado	2026-01-05 00:00:00+00	138	155	158	141	147	297	6	t	f
217	Talita Silva Mocado	2025-03-10 00:00:00+00	138	155	158	141	147	297	6	t	f
218	Tassio Lopes Mocado	2023-06-01 00:00:00+00	138	153	158	141	147	297	7	t	f
219	Tayane Silva Mocado	2023-06-01 00:00:00+00	93	153	158	141	147	297	8	t	f
220	Taynara Costa Mocado	2025-05-21 00:00:00+00	91	153	158	141	147	297	4	t	f
221	Thales Augusto Mocado	2023-08-24 00:00:00+00	93	153	158	141	147	297	4	t	f
222	Thalisson Frota Mocado	2025-02-03 00:00:00+00	93	152	158	141	147	297	8	t	f
224	Thiago Oliveira Mocado	2022-10-05 00:00:00+00	93	154	158	141	148	297	14	t	f
225	Thiago Teixeira Mocado	2025-03-06 00:00:00+00	122	153	158	141	148	297	\N	t	f
226	Thiego Silva Mocado	2023-05-02 00:00:00+00	97	153	158	141	147	297	8	t	f
227	Ulisses Teles Mocado	2024-03-06 00:00:00+00	97	155	158	141	147	297	6	t	f
228	Vanessa Silva Mocado	2025-05-15 00:00:00+00	109	154	158	141	147	297	4	t	f
229	Victor Santos Mocado	2020-08-10 00:00:00+00	138	153	158	141	148	297	8	t	f
231	Vitor Cavalcante Mocado	2022-07-05 00:00:00+00	89	153	158	141	148	297	\N	f	f
233	Vitoria Ferreira Mocado	2024-12-19 00:00:00+00	135	155	158	141	147	297	6	t	f
234	Wagner Abreu Mocado	2021-08-02 00:00:00+00	93	153	158	141	148	297	\N	f	f
235	Waleria Cavalcante Mocado	2024-04-01 00:00:00+00	91	154	160	141	148	297	6	t	f
237	Wesley Santos Mocado	2022-06-08 00:00:00+00	139	152	158	141	148	297	14	t	f
239	Willian Benevides Mocado	2023-07-19 00:00:00+00	83	153	158	141	147	297	7	t	f
240	Zilza Lopes Mocado	2024-08-21 00:00:00+00	131	154	158	141	148	297	6	t	f
241	Augusto Arraes Mocado	\N	92	155	158	142	148	297	\N	t	f
242	Breno Silva Mocado	2025-01-20 03:00:00+00	96	155	158	142	149	297	\N	t	f
243	Bruno Benevides Mocado	2025-05-26 03:00:00+00	75	155	158	142	148	297	\N	f	f
244	Caio Braz Mocado	2024-04-30 03:00:00+00	122	155	158	142	148	297	\N	f	f
245	Celso Neto Mocado	2024-07-01 03:00:00+00	94	155	158	142	148	297	\N	f	f
246	Celso Albuquerque Mocado	2022-10-14 03:00:00+00	93	155	158	142	148	297	\N	f	f
247	Cintia Amorim Mocado	2025-11-18 03:00:00+00	86	153	158	142	148	297	\N	f	f
248	Daiana Lins Mocado	2023-08-21 03:00:00+00	122	155	158	142	149	297	5	t	f
249	Daniel Costa Mocado	2024-06-03 03:00:00+00	94	155	158	142	148	297	\N	t	f
250	Davi Costa Mocado	2024-12-09 03:00:00+00	121	155	158	142	148	297	\N	t	f
251	Diego Santos Mocado	2023-09-22 03:00:00+00	121	153	158	142	149	297	\N	t	f
253	Éder Reverdito Mocado	2024-04-01 03:00:00+00	116	155	158	142	148	297	\N	f	f
254	Edson Sousa Mocado	2022-09-01 03:00:00+00	93	154	158	142	149	297	8	t	f
256	Felipe Sousa Mocado	2022-09-14 03:00:00+00	93	153	158	142	149	297	\N	t	f
257	Feliphe Alves Mocado	\N	121	155	158	142	148	297	\N	f	f
258	Gabriel Wilke Mocado	2024-06-24 00:00:00+00	129	155	158	142	148	297	\N	t	f
259	Gilvan Moura Mocado	2022-12-12 03:00:00+00	122	154	158	142	149	297	\N	t	f
260	Henrique Landim Mocado	2024-06-24 03:00:00+00	129	155	158	142	148	297	\N	t	f
261	Jaci Júnior Mocado	2023-03-20 03:00:00+00	93	155	158	142	149	297	8	t	f
262	João Pereira Mocado	2024-06-10 03:00:00+00	121	154	158	142	148	297	\N	t	f
263	Jonael Lemos Mocado	2026-04-27 13:02:01.397+00	121	155	158	142	148	297	\N	t	f
264	José Junior Mocado	2026-07-28 12:46:48.705+00	121	155	158	142	148	297	\N	t	f
265	José Neto Mocado	2023-09-22 03:00:00+00	121	154	158	142	148	297	\N	t	f
266	Kauã Silva Mocado	2025-08-04 03:00:00+00	121	154	158	142	148	297	\N	f	f
267	Kleiton Santos Mocado	2021-09-20 03:00:00+00	116	155	158	142	147	297	4	t	f
268	Luan Mascarenhas Mocado	2025-07-21 03:00:00+00	96	153	158	142	148	297	\N	f	f
269	Lucas Ramos Mocado	2024-01-22 03:00:00+00	121	153	158	142	148	297	\N	f	f
270	Luiza Filgueira Mocado	2022-08-19 03:00:00+00	95	153	158	142	149	297	\N	t	f
271	Maciel Serafim Mocado	2026-04-23 03:00:00+00	122	155	158	141	149	297	5	t	f
272	Marcelo Junior Mocado	\N	129	155	158	142	148	297	\N	t	f
273	Marcos Francisco Mocado	\N	75	153	158	142	149	297	\N	t	f
274	Michel Barbosa Mocado	2024-04-01 03:00:00+00	86	153	158	142	149	297	\N	f	f
275	Nilo Barroso Mocado	2025-04-28 03:00:00+00	93	155	158	142	148	297	\N	f	f
276	Pablo Guto Mocado	\N	121	153	158	142	149	297	\N	t	f
277	Victoria Mangueira Mocado	2024-07-08 03:00:00+00	140	154	158	142	148	297	\N	f	f
278	Wagner Lemos Mocado	2023-09-18 03:00:00+00	121	154	158	142	148	297	\N	t	f
284	Daniel Moreira Mocado	2025-12-15 03:00:00+00	121	152	158	141	148	297	\N	t	f
285	Glace Sousa Mocado	2026-01-19 03:00:00+00	101	153	158	142	148	297	\N	f	f
286	Guilherme Azevedo Mocado	2025-03-23 03:00:00+00	121	153	158	141	147	297	7	t	f
287	Flauberth Júnior Mocado	2026-03-23 03:00:00+00	121	153	158	141	147	297	7	t	f
288	Caroliny Bandeira Mocado	2025-03-04 03:00:00+00	136	154	158	141	147	297	7	t	f
289	William Nascimento Mocado	2025-03-02 03:00:00+00	138	153	158	141	147	297	7	t	f
290	Kelvin Azevedo Mocado	2025-03-23 03:00:00+00	121	152	158	141	147	297	8	t	f
291	Rafael Jucá Mocado	2024-01-01 03:00:00+00	127	157	158	142	147	297	\N	t	f
292	Lucas Costa Mocado	2026-02-19 03:00:00+00	121	154	158	141	147	297	4	t	f
293	Alan Moreira Mocado	2026-04-10 03:00:00+00	136	154	158	141	147	297	7	t	f
294	Alvin Azevedo Mocado	2026-03-16 03:00:00+00	137	154	158	141	147	297	7	t	f
295	Igor Afonso Mocado	2026-02-04 03:00:00+00	124	155	158	141	147	297	7	t	f
296	Paulo Castro Mocado	2026-04-14 03:00:00+00	138	153	158	142	148	297	\N	f	f
297	Ana Mendonça Mocado	2026-04-20 03:00:00+00	139	152	158	141	147	297	14	t	f
298	Felipe Madruga Mocado	2026-04-20 03:00:00+00	139	152	158	141	147	297	14	t	f
299	Isaac Menezes Mocado	2026-04-20 03:00:00+00	139	152	158	141	147	297	14	t	f
300	Ivaneudo Rocha Mocado	2026-05-11 03:00:00+00	128	151	158	141	147	297	\N	t	f
301	João Braga Mocado	2026-05-01 03:00:00+00	139	152	158	141	147	297	\N	f	f
302	José Costa Mocado	2026-04-20 03:00:00+00	139	152	158	141	147	297	14	t	f
303	KENNEDY VASCONCELOS Mocado	2026-04-20 03:00:00+00	139	152	158	141	147	297	14	t	f
304	Taua Pessoa Mocado	2026-04-20 03:00:00+00	139	152	158	141	147	297	14	t	f
305	Lucas Frota Mocado	2026-05-11 03:00:00+00	138	153	158	142	147	297	7	t	f
306	Lucas Oliveira Mocado	2026-05-13 03:00:00+00	89	154	158	142	148	297	\N	t	f
307	Jonathan Silva Mocado	2018-09-04 03:00:00+00	93	156	158	142	148	297	8	t	f
308	Isaac (t) Mocado	2026-05-29 18:18:18.434+00	116	155	158	141	147	297	\N	f	t
309	Luan Lima Mocado	2026-06-03 03:00:00+00	138	154	159	141	147	297	\N	t	f
310	Ian Cruz Mocado	2026-06-01 03:00:00+00	138	154	159	141	147	297	6	t	f
311	Robson Junior Mocado	2026-06-01 03:00:00+00	138	154	159	141	147	297	6	t	f
312	Jéssica Campos Mocado	2026-05-20 03:00:00+00	138	154	158	141	147	297	7	t	f
313	Cássio Pinho Mocado	2025-09-15 03:00:00+00	94	153	158	142	148	297	\N	t	f
314	Felipe Aguiar Mocado	2025-09-15 03:00:00+00	94	153	158	142	148	297	\N	f	f
315	Matheus Martins Mocado	2026-02-09 03:00:00+00	93	152	158	142	148	297	\N	f	f
316	Maximiliano Vale Mocado	2026-02-23 03:00:00+00	92	153	158	142	148	297	\N	f	f
317	Aliton Silva Mocado	2025-12-15 03:00:00+00	98	153	158	142	147	297	7	t	f
318	Flávio Storch Mocado	2024-10-01 03:00:00+00	75	155	158	141	147	297	16	t	f
319	Hudson Silva Mocado	2024-08-01 03:00:00+00	131	155	160	142	148	297	16	t	f
320	Joice Nicoli Mocado	2025-11-10 03:00:00+00	138	154	158	141	147	297	16	t	f
321	Márcia Cavalcante Mocado	2025-12-09 03:00:00+00	93	155	158	141	147	297	4	t	f
322	Murilo Silva Mocado	2024-02-07 03:00:00+00	125	156	158	141	147	297	16	t	f
326	Sarah Silva Mocado	2025-01-02 03:00:00+00	122	153	158	141	148	297	\N	f	f
327	Matheus Araujo Mocado	2026-04-01 03:00:00+00	121	153	158	142	148	297	\N	t	f
328	Joaquim Neto Mocado	2026-07-20 00:00:00+00	78	154	158	141	147	297	8	t	f
329	Eider Silva Mocado	2026-07-01 00:00:00+00	122	155	158	142	148	297	\N	t	f
330	Bruno Silva Mocado	2026-04-20 03:00:00+00	93	152	158	141	148	297	14	t	f
331	Flavia Gomes Mocado	2026-08-10 00:00:00+00	91	155	158	141	147	297	\N	t	f
332	Priscila Souza Mocado	2025-09-17 03:00:00+00	109	154	158	141	147	297	4	t	f
333	Edson Junior Mocado	2026-09-14 00:00:00+00	138	153	158	141	147	\N	\N	t	f
334	Davi Armes Mocado	2026-09-01 00:00:00+00	93	155	158	141	147	\N	\N	t	f
335	Rosicleide Luz Mocado	2026-09-01 00:00:00+00	138	155	158	141	147	\N	\N	t	f
336	Eliana Oliveira Mocado	2026-10-07 00:00:00+00	86	154	158	141	147	\N	\N	t	f
\.


--
-- TOC entry 3623 (class 0 OID 95634)
-- Dependencies: 225
-- Data for Name: contratos; Type: TABLE DATA; Schema: InHire; Owner: postgres
--

COPY "InHire".contratos (id, nome_contrato, data_inicio, data_termino, id_situacao, id_centro_custo, id_preposto, status, deletado) FROM stdin;
1	Contrato 1	2021-06-26	2026-07-25	217	63	1	t	f
2	Contrato 2	2020-11-10	2026-06-10	217	60	1	t	f
3	Contrato 3	2025-08-12	2026-08-11	217	65	267	t	f
4	Contrato 4	2026-07-17	2027-07-17	216	70	240	t	f
5	Contrato 5	2025-12-15	2026-12-15	239	74	240	t	f
6	Contrato 6	2025-12-13	2026-12-13	239	73	240	t	f
7	Contrato 7	2025-04-11	2027-04-30	216	68	75	t	f
8	Contrato 8	2025-09-18	2026-09-17	217	67	79	t	f
9	Contrato 9	2026-04-06	2027-09-30	216	7	260	t	f
12	Contrato 12	2026-04-01	2027-04-30	216	278	260	t	f
13	Contrato 13	2025-01-01	2026-05-31	217	64	253	t	f
14	Contrato 14	2026-03-30	2027-03-30	216	287	87	t	f
15	Contrato 15	2026-09-01	2028-08-31	216	271	137	t	f
16	Contrato 16	2023-09-15	2026-10-30	303	72	319	t	f
\.


--
-- TOC entry 3633 (class 0 OID 95789)
-- Dependencies: 235
-- Data for Name: demanda_skills; Type: TABLE DATA; Schema: InHire; Owner: postgres
--

COPY "InHire".demanda_skills (id, id_demanda, id_skill, status, deletado) FROM stdin;
1	11	23	t	f
2	11	16	t	f
3	11	98	t	f
4	11	41	t	f
5	11	58	t	f
6	11	59	t	f
7	11	89	t	f
8	11	111	t	f
9	4	18	t	f
10	4	20	t	f
11	4	19	t	f
12	4	59	t	f
13	4	61	t	f
14	4	55	t	f
15	27	18	t	f
16	27	20	t	f
17	27	19	t	f
18	27	58	t	f
19	27	59	t	f
20	27	56	t	f
21	27	61	t	f
22	27	55	t	f
23	27	1	t	f
24	27	12	t	f
25	27	3	t	f
26	27	9	t	f
27	27	50	t	f
28	27	52	t	f
29	27	65	t	f
30	27	72	t	f
31	27	66	t	f
32	27	74	t	f
33	27	99	t	f
34	27	103	t	f
35	27	107	t	f
36	27	110	t	f
37	28	18	t	f
38	28	20	t	f
39	28	19	t	f
40	28	59	t	f
41	28	58	t	f
42	28	56	t	f
43	28	55	t	f
44	28	103	t	f
45	28	99	t	f
46	28	107	t	f
47	28	110	t	f
48	28	66	t	f
49	28	41	t	f
50	28	40	t	f
51	28	2	t	f
52	28	9	t	f
53	28	3	t	f
54	28	12	t	f
55	29	41	t	f
56	29	40	t	f
57	31	41	t	f
58	33	111	t	f
59	33	3	t	f
60	33	40	t	f
61	33	41	t	f
62	33	50	t	f
63	33	119	t	f
64	34	40	t	f
65	34	41	t	f
66	34	18	t	f
67	34	20	t	f
68	34	65	t	f
69	34	119	t	f
70	34	99	t	f
71	34	107	t	f
72	34	111	t	f
73	35	3	t	f
74	35	18	t	f
75	35	21	t	f
76	35	19	t	f
77	35	20	t	f
78	35	41	t	f
79	35	40	t	f
80	35	50	t	f
81	35	119	t	f
82	35	59	t	f
83	35	56	t	f
84	35	55	t	f
85	35	61	t	f
86	35	58	t	f
87	35	65	t	f
88	35	66	t	f
89	36	3	t	f
90	36	18	t	f
91	36	60	t	f
92	41	41	t	f
93	41	29	t	f
94	41	40	t	f
95	41	3	t	f
96	41	50	t	f
97	41	119	t	f
98	41	18	t	f
99	41	65	t	f
100	41	66	t	f
101	41	103	t	f
102	41	110	t	f
103	50	20	t	f
104	50	62	t	f
105	50	58	t	f
106	50	38	t	f
107	51	18	t	f
108	51	20	t	f
109	51	58	t	f
110	51	62	t	f
111	51	38	t	f
112	51	115	t	f
113	51	119	t	f
114	51	114	t	f
115	52	18	t	f
116	52	20	t	f
117	52	62	t	f
118	52	58	t	f
119	52	38	t	f
120	52	106	t	f
121	52	102	t	f
122	53	20	t	f
123	53	18	t	f
124	53	58	t	f
125	53	62	t	f
126	53	38	t	f
127	53	106	t	f
128	53	102	t	f
129	53	104	t	f
130	54	20	t	f
131	54	18	t	f
132	54	58	t	f
133	54	62	t	f
134	54	61	t	f
135	55	18	t	f
136	55	20	t	f
137	55	58	t	f
138	55	62	t	f
139	55	38	t	f
140	55	106	t	f
141	56	18	t	f
142	56	20	t	f
143	56	61	t	f
144	56	58	t	f
145	56	62	t	f
146	56	38	t	f
147	56	106	t	f
148	57	18	t	f
149	57	20	t	f
150	57	19	t	f
151	57	58	t	f
152	57	62	t	f
153	57	61	t	f
154	57	38	t	f
155	57	106	t	f
156	58	18	t	f
157	58	20	t	f
158	58	19	t	f
159	58	58	t	f
160	58	62	t	f
161	58	38	t	f
162	58	106	t	f
163	59	18	t	f
164	59	20	t	f
165	59	58	t	f
166	59	62	t	f
167	59	38	t	f
168	59	106	t	f
169	60	18	t	f
170	60	20	t	f
171	60	38	t	f
172	60	58	t	f
173	60	62	t	f
174	60	106	t	f
175	61	106	t	f
176	61	58	t	f
177	61	61	t	f
178	61	62	t	f
179	62	18	t	f
180	62	20	t	f
181	62	19	t	f
182	62	58	t	f
183	62	62	t	f
184	62	61	t	f
185	62	59	t	f
186	62	38	t	f
187	62	106	t	f
188	63	18	t	f
189	63	20	t	f
190	63	58	t	f
191	63	62	t	f
192	63	61	t	f
193	63	106	t	f
194	64	18	t	f
195	64	20	t	f
196	64	58	t	f
197	64	62	t	f
198	64	61	t	f
199	64	38	t	f
200	64	106	t	f
201	65	18	t	f
202	65	20	t	f
203	65	38	t	f
204	65	58	t	f
205	65	62	t	f
206	65	61	t	f
207	65	106	t	f
208	74	18	t	f
209	74	20	t	f
210	74	58	t	f
211	74	62	t	f
212	74	61	t	f
213	74	38	t	f
214	74	106	t	f
215	75	18	t	f
216	75	58	t	f
217	75	62	t	f
218	75	61	t	f
219	75	38	t	f
220	75	106	t	f
221	76	20	t	f
222	76	58	t	f
223	76	62	t	f
224	76	38	t	f
225	76	106	t	f
226	77	20	t	f
227	77	58	t	f
228	77	62	t	f
229	77	61	t	f
230	77	38	t	f
231	77	106	t	f
232	79	36	t	f
233	79	41	t	f
234	79	50	t	f
235	79	52	t	f
236	79	103	t	f
237	79	98	t	f
238	79	115	t	f
239	16	21	t	f
240	16	14	t	f
241	16	59	t	f
242	16	61	t	f
243	16	41	t	f
244	16	50	t	f
245	16	84	t	f
246	16	98	t	f
247	16	109	t	f
248	16	111	t	f
249	82	16	t	f
250	82	19	t	f
251	83	60	t	f
252	83	61	t	f
253	83	43	t	f
254	83	41	t	f
255	83	111	t	f
256	85	3	t	f
257	85	20	t	f
258	85	18	t	f
259	85	22	t	f
260	85	41	t	f
261	85	48	t	f
262	85	119	t	f
263	85	59	t	f
264	85	56	t	f
265	85	61	t	f
266	85	66	t	f
267	85	99	t	f
268	85	103	t	f
269	85	110	t	f
270	86	41	t	f
271	86	40	t	f
272	86	3	t	f
273	86	2	t	f
274	86	50	t	f
275	86	115	t	f
276	86	119	t	f
277	86	65	t	f
278	86	66	t	f
279	86	110	t	f
280	18	16	t	f
281	18	38	t	f
282	87	2	t	f
283	87	41	t	f
284	87	50	t	f
285	87	59	t	f
286	87	61	t	f
287	87	56	t	f
288	87	66	t	f
289	87	103	t	f
290	87	111	t	f
291	87	20	t	f
292	87	18	t	f
317	118	20	t	f
318	118	18	t	f
319	118	2	t	f
320	118	3	t	f
321	118	41	t	f
322	118	50	t	f
323	118	119	t	f
324	118	117	t	f
325	118	61	t	f
326	118	59	t	f
327	118	66	t	f
328	118	99	t	f
329	118	110	t	f
330	119	3	t	f
331	119	40	t	f
332	119	50	t	f
333	119	117	t	f
334	119	60	t	f
335	119	109	t	f
336	125	23	t	f
337	125	41	t	f
\.


--
-- TOC entry 3627 (class 0 OID 95705)
-- Dependencies: 229
-- Data for Name: demandas; Type: TABLE DATA; Schema: InHire; Owner: postgres
--

COPY "InHire".demandas (id, nome_demanda, id_gerente, id_contrato, id_tipo_servico, id_metodologia, id_andamento_demanda, id_grupo, dt_inicio_demanda, dt_termino_demanda_prevista, compartilha_profissionais, pertence_pmo, status, deletado) FROM stdin;
1	Demanda 1	119	1	275	233	283	\N	2026-05-25	2026-05-25	f	f	t	f
2	Demanda 2	87	2	163	233	283	\N	2026-05-25	2026-05-25	f	f	t	f
3	Demanda 3	267	3	164	233	281	\N	2026-05-25	2026-05-25	f	t	t	f
4	Demanda 4	202	4	275	231	284	309	2026-05-25	2026-12-30	f	t	t	f
5	Demanda 5	240	5	275	231	282	\N	2026-07-06	2026-07-10	f	t	t	f
6	Demanda 6	235	6	163	232	285	309	2026-01-26	2026-05-29	f	t	t	f
7	Demanda 7	75	7	163	233	283	\N	2026-05-25	2026-05-25	f	f	t	f
8	Demanda 8	79	8	163	233	283	\N	2026-05-25	2026-05-25	f	f	t	f
11	Demanda 11	94	9	163	231	281	310	2025-10-27	2026-09-25	t	t	t	f
12	Demanda 12	94	9	163	231	283	\N	2026-05-25	2026-05-25	f	f	t	f
13	Demanda 13	137	9	163	233	283	\N	2026-05-25	2026-05-25	f	f	t	f
14	Demanda 14	260	12	275	232	283	\N	2026-05-25	2026-05-25	f	f	t	f
15	Demanda 15	258	9	167	233	283	\N	2026-05-25	2026-05-25	t	f	t	f
16	Demanda 16	235	6	163	232	281	\N	2025-10-29	2026-06-05	t	t	t	f
17	Demanda 17	240	6	275	232	283	\N	2026-05-25	2026-05-25	f	f	t	f
18	Demanda 18	258	9	167	237	280	309	2025-09-16	2026-07-17	f	t	t	f
19	Demanda 19	253	13	275	232	283	\N	2026-05-25	2026-05-25	f	f	t	f
20	Demanda 20	260	9	167	232	283	\N	2026-05-25	2026-05-25	f	f	t	f
21	Demanda 21	291	9	167	232	283	\N	2026-05-25	2026-05-25	f	f	t	f
22	Demanda 22	260	9	167	232	283	\N	2026-05-25	2026-05-25	f	f	t	f
23	Demanda 23	260	9	163	232	283	\N	2026-05-25	2026-05-25	f	f	t	f
24	Demanda 24	260	9	164	232	283	\N	2026-05-25	2026-05-25	f	f	t	f
25	Demanda 25	260	9	167	232	283	\N	2026-05-25	2026-05-25	t	f	t	f
26	Demanda 26	272	9	163	232	281	309	2026-04-20	2026-05-22	t	f	t	f
27	Demanda 27	202	4	275	231	284	\N	2026-04-09	2027-01-29	f	t	t	f
28	Demanda 28	202	4	275	231	280	\N	2026-04-22	2026-11-30	f	t	t	f
29	Demanda 29	202	4	275	231	280	\N	2026-01-05	2026-09-30	f	t	t	f
30	Demanda 30	202	4	275	231	281	309	2026-05-11	2026-08-31	f	t	t	f
31	Demanda 31	202	4	275	231	281	\N	2026-03-10	2026-08-31	f	t	t	f
32	Demanda 32	202	4	275	231	281	\N	2026-04-27	2026-06-19	f	t	t	f
33	Demanda 33	202	4	275	231	281	\N	2026-03-30	2026-05-29	f	t	t	f
34	Demanda 34	202	4	275	231	281	\N	2026-06-11	2026-08-17	f	t	t	f
35	Demanda 35	202	4	275	231	284	\N	2026-04-08	2026-10-09	f	t	t	f
36	Demanda 36	202	4	275	231	281	\N	2026-03-16	2026-08-17	f	t	t	f
37	Demanda 37	202	4	275	231	281	\N	2026-02-09	2026-06-10	f	t	t	f
38	Demanda 38	202	4	275	231	281	\N	2026-05-11	2026-05-29	f	t	t	f
39	Demanda 39	202	4	275	232	280	\N	2026-02-17	2026-09-04	f	t	t	f
40	Demanda 40	202	4	275	231	280	\N	2026-03-23	2026-11-06	f	t	t	f
41	Demanda 41	202	4	275	231	281	\N	2025-11-14	2026-08-31	f	t	t	f
42	Demanda 42	202	4	275	231	281	\N	2023-03-11	2025-06-30	f	t	t	f
44	Demanda 44	202	4	275	231	283	\N	2027-01-04	2027-02-26	f	t	t	f
45	Demanda 45	202	4	275	231	283	\N	2027-01-04	2027-02-26	f	t	t	f
46	Demanda 46	202	4	275	231	283	\N	2027-01-04	2027-03-31	f	t	t	f
47	Demanda 47	202	4	275	231	283	\N	2027-02-08	2027-04-30	f	t	t	f
48	Demanda 48	202	4	275	231	283	\N	2027-01-04	2027-02-22	f	t	t	f
49	Demanda 49	202	7	163	231	283	\N	2027-03-08	2027-05-31	f	t	t	f
50	Demanda 50	267	3	164	232	281	\N	2022-01-04	2022-12-10	f	t	t	f
51	Demanda 51	267	3	164	232	281	\N	2021-11-05	2022-10-04	f	t	t	f
52	Demanda 52	267	3	164	232	281	\N	2023-01-10	2023-11-19	f	t	t	f
53	Demanda 53	267	3	164	232	281	\N	2023-04-10	2023-12-11	f	t	t	f
54	Demanda 54	267	3	164	232	281	\N	2023-06-08	2023-12-21	f	t	t	f
55	Demanda 55	267	3	164	232	281	\N	2024-02-25	2024-09-10	f	t	t	f
56	Demanda 56	267	3	164	232	281	\N	2023-08-10	2023-10-10	f	t	t	f
57	Demanda 57	267	3	164	232	281	\N	2024-04-10	2024-06-22	f	t	t	f
58	Demanda 58	267	3	164	232	281	\N	2024-07-02	2024-12-27	f	t	t	f
59	Demanda 59	267	3	164	232	281	\N	2025-08-20	2025-10-21	f	t	t	f
60	Demanda 60	267	3	164	232	281	\N	2026-01-03	2026-06-05	f	t	t	f
61	Demanda 61	267	3	164	232	281	\N	2026-03-10	2026-07-10	f	t	t	f
62	Demanda 62	267	3	164	232	281	\N	2025-06-10	2026-07-20	f	t	t	f
63	Demanda 63	267	3	164	232	281	\N	2026-02-11	2026-07-10	f	t	t	f
64	Demanda 64	267	3	164	232	281	\N	2025-11-10	2026-06-29	f	f	t	f
65	Demanda 65	267	3	164	232	281	\N	2026-01-22	2026-07-07	f	t	t	f
66	Demanda 66	267	3	164	232	283	\N	2025-01-01	2025-06-20	f	t	t	f
67	Demanda 67	267	3	164	232	283	\N	2025-02-03	2025-08-08	f	t	t	f
68	Demanda 68	267	3	164	232	283	\N	2025-05-05	2025-08-14	f	t	t	f
69	Demanda 69	267	3	164	232	283	\N	2023-05-02	2024-02-02	f	t	t	f
70	Demanda 70	267	3	164	232	283	\N	2023-02-02	2023-12-12	f	t	t	f
71	Demanda 71	267	3	164	232	283	\N	2023-11-06	2024-08-08	f	t	t	f
72	Demanda 72	267	3	164	232	283	\N	2023-10-25	2024-04-04	f	f	t	f
73	Demanda 73	267	3	164	232	283	\N	2023-05-31	2023-09-10	f	t	t	f
74	Demanda 74	267	3	164	232	284	\N	2026-01-08	2026-08-02	f	t	t	f
75	Demanda 75	267	3	164	232	281	\N	2026-01-05	2026-08-08	f	t	t	f
76	Demanda 76	267	3	164	232	281	\N	2026-01-15	2026-08-01	f	t	t	f
77	Demanda 77	267	3	164	232	281	\N	2026-01-22	2026-07-30	f	t	t	f
78	Demanda 78	240	5	275	231	281	\N	2023-12-15	2025-10-02	f	t	t	f
79	Demanda 79	240	5	275	231	284	309	2026-04-01	2026-12-15	f	t	t	f
80	Demanda 80	94	9	163	231	284	310	2026-08-03	2026-12-24	f	t	t	f
81	Demanda 81	258	15	163	231	283	\N	2026-09-01	2028-08-31	f	t	t	f
82	Demanda 82	267	9	163	231	283	\N	2027-01-01	2027-12-31	f	t	t	f
83	Demanda 83	202	4	275	231	280	309	2026-07-13	2026-10-02	f	t	t	f
84	Demanda 84	319	16	164	232	282	\N	2023-09-15	2027-09-14	f	f	t	f
85	Demanda 85	202	4	275	231	283	\N	2026-07-27	2027-02-12	f	f	t	f
86	Demanda 86	202	4	275	231	284	309	2026-09-03	2026-12-30	f	t	t	f
87	Demanda 87	202	4	275	231	284	\N	2026-08-18	2026-11-16	f	t	t	f
108	Demanda 108	202	4	275	232	284	\N	2026-01-01	2028-12-31	f	f	t	f
109	Demanda 109	202	1	275	232	284	\N	2025-01-01	2028-12-31	f	f	f	t
118	Demanda 118	202	4	275	231	284	309	2026-09-08	2027-01-29	f	t	t	f
119	Demanda 119	202	4	275	231	284	309	2026-09-08	2026-11-19	f	t	t	f
120	Demanda 120	235	6	163	231	283	309	2026-09-28	2027-05-28	f	t	t	f
121	Demanda 121	235	6	164	231	284	\N	2026-09-01	2026-10-30	f	f	t	f
122	Demanda 122	267	6	163	231	283	\N	2026-09-28	2027-03-26	f	t	t	f
123	Demanda 123	267	6	163	231	283	\N	2026-09-28	2027-03-26	f	t	t	f
124	Demanda 124	267	6	163	231	283	\N	2026-09-28	2027-02-26	f	f	f	t
125	Demanda 125	94	9	163	231	284	310	2026-10-12	2026-10-29	f	t	t	f
126	Demanda 126	272	9	163	231	282	310	2026-10-01	2026-12-18	t	f	t	f
\.


--
-- TOC entry 3621 (class 0 OID 95623)
-- Dependencies: 223
-- Data for Name: dominios; Type: TABLE DATA; Schema: InHire; Owner: postgres
--

COPY "InHire".dominios (id, tipo_dominio, valor_dominio, descricao, status, deletado) FROM stdin;
1	CENTRO_CUSTO	Centro de custo 1	Centro de custo 1	t	t
2	CENTRO_CUSTO	Centro de custo 2	Centro de custo 2	t	t
3	CENTRO_CUSTO	Centro de custo 3	Centro de custo 3	t	t
4	CENTRO_CUSTO	Centro de custo 4	Centro de custo 4	t	t
5	CENTRO_CUSTO	Centro de custo 5	Centro de custo 5	t	t
6	CENTRO_CUSTO	Centro de custo 6	Centro de custo 6	t	t
7	CENTRO_CUSTO	Centro de custo 7	Centro de custo 7	t	f
8	CENTRO_CUSTO	Centro de custo 8	Centro de custo 8	t	t
9	CENTRO_CUSTO	Centro de custo 9	Centro de custo 9	t	t
10	CENTRO_CUSTO	Centro de custo 10	Centro de custo 10	t	t
11	CENTRO_CUSTO	Centro de custo 11	Centro de custo 11	t	t
12	CENTRO_CUSTO	Centro de custo 12	Centro de custo 12	t	t
13	CENTRO_CUSTO	Centro de custo 13	Centro de custo 13	t	t
14	CENTRO_CUSTO	Centro de custo 14	Centro de custo 14	t	t
15	CENTRO_CUSTO	Centro de custo 15	Centro de custo 15	t	t
16	CENTRO_CUSTO	Centro de custo 16	Centro de custo 16	t	t
17	CENTRO_CUSTO	Centro de custo 17	Centro de custo 17	t	t
18	CENTRO_CUSTO	Centro de custo 18	Centro de custo 18	t	t
19	CENTRO_CUSTO	Centro de custo 19	Centro de custo 19	t	t
20	CENTRO_CUSTO	Centro de custo 20	Centro de custo 20	t	t
21	CENTRO_CUSTO	Centro de custo 21	Centro de custo 21	t	t
22	CENTRO_CUSTO	Centro de custo 22	Centro de custo 22	t	t
23	CENTRO_CUSTO	Centro de custo 23	Centro de custo 23	t	t
24	CENTRO_CUSTO	Centro de custo 24	Centro de custo 24	t	t
25	CENTRO_CUSTO	Centro de custo 25	Centro de custo 25	t	t
26	CENTRO_CUSTO	Centro de custo 26	Centro de custo 26	t	t
27	CENTRO_CUSTO	Centro de custo 27	Centro de custo 27	t	t
28	CENTRO_CUSTO	Centro de custo 28	Centro de custo 28	t	t
29	CENTRO_CUSTO	Centro de custo 29	Centro de custo 29	t	t
30	CENTRO_CUSTO	Centro de custo 30	Centro de custo 30	t	t
31	CENTRO_CUSTO	Centro de custo 31	Centro de custo 31	t	t
32	CENTRO_CUSTO	Centro de custo 32	Centro de custo 32	t	t
33	CENTRO_CUSTO	Centro de custo 33	Centro de custo 33	t	t
34	CENTRO_CUSTO	Centro de custo 34	Centro de custo 34	t	t
35	CENTRO_CUSTO	Centro de custo 35	Centro de custo 35	t	t
36	CENTRO_CUSTO	Centro de custo 36	Centro de custo 36	t	t
37	CENTRO_CUSTO	Centro de custo 37	Centro de custo 37	t	t
38	CENTRO_CUSTO	Centro de custo 38	Centro de custo 38	t	t
39	CENTRO_CUSTO	Centro de custo 39	Centro de custo 39	t	t
40	CENTRO_CUSTO	Centro de custo 40	Centro de custo 40	t	t
41	CENTRO_CUSTO	Centro de custo 41	Centro de custo 41	t	t
42	CENTRO_CUSTO	Centro de custo 42	Centro de custo 42	t	t
43	CENTRO_CUSTO	Centro de custo 43	Centro de custo 43	t	t
44	CENTRO_CUSTO	Centro de custo 44	Centro de custo 44	t	t
45	CENTRO_CUSTO	Centro de custo 45	Centro de custo 45	t	t
46	CENTRO_CUSTO	Centro de custo 46	Centro de custo 46	t	t
47	CENTRO_CUSTO	Centro de custo 47	Centro de custo 47	t	t
48	CENTRO_CUSTO	Centro de custo 48	Centro de custo 48	t	t
49	CENTRO_CUSTO	Centro de custo 49	Centro de custo 49	t	t
50	CENTRO_CUSTO	Centro de custo 50	Centro de custo 50	t	t
51	CENTRO_CUSTO	Centro de custo 51	Centro de custo 51	t	t
52	CENTRO_CUSTO	Centro de custo 52	Centro de custo 52	t	t
53	CENTRO_CUSTO	Centro de custo 53	Centro de custo 53	t	f
54	CENTRO_CUSTO	Centro de custo 54	Centro de custo 54	t	t
55	CENTRO_CUSTO	Centro de custo 55	Centro de custo 55	t	t
56	CENTRO_CUSTO	Centro de custo 56	Centro de custo 56	t	t
57	CENTRO_CUSTO	Centro de custo 57	Centro de custo 57	t	t
58	CENTRO_CUSTO	Centro de custo 58	Centro de custo 58	t	t
59	CENTRO_CUSTO	Centro de custo 59	Centro de custo 59	t	t
60	CENTRO_CUSTO	Centro de custo 60	Centro de custo 60	t	f
61	CENTRO_CUSTO	Centro de custo 61	Centro de custo 61	t	t
62	CENTRO_CUSTO	Centro de custo 62	Centro de custo 62	t	t
63	CENTRO_CUSTO	Centro de custo 63	Centro de custo 63	t	f
64	CENTRO_CUSTO	Centro de custo 64	Centro de custo 64	t	f
65	CENTRO_CUSTO	Centro de custo 65	Centro de custo 65	t	f
66	CENTRO_CUSTO	Centro de custo 66	Centro de custo 66	t	f
67	CENTRO_CUSTO	Centro de custo 67	Centro de custo 67	t	f
68	CENTRO_CUSTO	Centro de custo 68	Centro de custo 68	t	f
69	CENTRO_CUSTO	Centro de custo 69	Centro de custo 69	t	f
70	CENTRO_CUSTO	Centro de custo 70	Centro de custo 70	t	f
71	CENTRO_CUSTO	Centro de custo 71	Centro de custo 71	t	f
72	CENTRO_CUSTO	Centro de custo 72	Centro de custo 72	t	f
73	CENTRO_CUSTO	Centro de custo 73	Centro de custo 73	t	f
74	CENTRO_CUSTO	Centro de custo 74	Centro de custo 74	t	f
75	CARGO	Administrador de Bancos de Dados	Administrador de Bancos de Dados	t	f
76	CARGO	Analista de Bi	Analista de Bi	t	f
77	CARGO	Analista de Controladoria	Analista de Controladoria	t	f
78	CARGO	Analista de Dados	Analista de Dados	t	f
79	CARGO	Analista de Desenvolvimento e Operações	Analista de Desenvolvimento e Operações	t	f
80	CARGO	Analista de Dp	Analista de Dp	t	f
81	CARGO	Analista de Endomarketing	Analista de Endomarketing	t	f
82	CARGO	Analista de Gente e Cultura	Analista de Gente e Cultura	t	f
83	CARGO	Analista de Infraestrutura	Analista de Infraestrutura	t	f
84	CARGO	Analista de Licitações	Analista de Licitações	t	f
85	CARGO	Analista de Marketing	Analista de Marketing	t	f
86	CARGO	Analista de Negócios	Analista de Negócios	t	f
87	CARGO	Analista de Processos e Qualidade	Analista de Processos e Qualidade	t	f
88	CARGO	Analista de Projetos	Analista de Projetos	t	f
89	CARGO	Analista de Qualidade	Analista de Qualidade	t	f
90	CARGO	Analista de Redes e Infraestrutura	Analista de Redes e Infraestrutura	t	f
91	CARGO	Analista de Requisitos	Analista de Requisitos	t	f
92	CARGO	Analista de Segurança da Informação	Analista de Segurança da Informação	t	f
93	CARGO	Analista de Sistemas	Analista de Sistemas	t	f
94	CARGO	Analista de Sistemas Desenvolvedor	Analista de Sistemas Desenvolvedor	t	f
95	CARGO	Analista de Sistemas Requisitos	Analista de Sistemas Requisitos	t	f
96	CARGO	Analista de Sistemas Teste	Analista de Sistemas Teste	t	f
97	CARGO	Analista de Suporte	Analista de Suporte	t	f
98	CARGO	Analista Devops	Analista Devops	t	f
99	CARGO	Analista Financeiro	Analista Financeiro	t	f
100	CARGO	Arquiteto de Software	Arquiteto de Software	t	f
101	CARGO	Assistente Administrativo	Assistente Administrativo	t	f
102	CARGO	Assistente Contábil	Assistente Contábil	t	f
103	CARGO	Assistente de Dp	Assistente de Dp	t	f
104	CARGO	Assistente de Gente e Cultura	Assistente de Gente e Cultura	t	f
105	CARGO	Assistente de Licitações e Negócio	Assistente de Licitações e Negócio	t	f
106	CARGO	Assistente de Rh	Assistente de Rh	t	f
107	CARGO	Assistente Financeiro	Assistente Financeiro	t	f
108	CARGO	Assistente Informática	Assistente Informática	t	f
109	CARGO	Assistente Técnico	Assistente Técnico	t	f
110	CARGO	Auxiliar Administrativo	Auxiliar Administrativo	t	f
111	CARGO	Continuo	Continuo	t	f
112	CARGO	Coord Servicos de Tecnologia	Coord Servicos de Tecnologia	t	f
113	CARGO	Coordenador de Dens Organizacional	Coordenador de Dens Organizacional	t	f
114	CARGO	Coordenador de Infraestrutura	Coordenador de Infraestrutura	t	f
115	CARGO	Coordenador de Infraestrutura da Ti	Coordenador de Infraestrutura da Ti	t	f
116	CARGO	Coordenador de Projetos	Coordenador de Projetos	t	f
117	CARGO	Coordenador Logística	Coordenador Logística	t	f
118	CARGO	Coordenador Financeiro	Coordenador Financeiro	t	f
119	CARGO	Coordenador	Coordenador	t	f
120	CARGO	Coordenador de Dp	Coordenador de Dp	t	f
121	CARGO	Desenvolvedor	Desenvolvedor	t	f
122	CARGO	Desenvolvedor Full Stack	Desenvolvedor Full Stack	t	f
123	CARGO	Engenheiro de Soluções	Engenheiro de Soluções	t	f
124	CARGO	Engenheiro de Telecomunicações	Engenheiro de Telecomunicações	t	f
125	CARGO	Especialista Em Infraestrutura	Especialista Em Infraestrutura	t	f
126	CARGO	Especialista Em Processos	Especialista Em Processos	t	f
127	CARGO	Especialista Em Segurança Ti	Especialista Em Segurança Ti	t	f
128	CARGO	Estagiário	Estagiário	t	f
129	CARGO	Gerente de Projetos	Gerente de Projetos	t	f
130	CARGO	Motorista	Motorista	t	f
131	CARGO	Preposto	Preposto	t	f
132	CARGO	Recepcionista	Recepcionista	t	f
133	CARGO	Secretaria Executiva	Secretaria Executiva	t	f
134	CARGO	Servicos Gerais	Servicos Gerais	t	f
135	CARGO	Tecnico de Informática	Tecnico de Informática	t	f
136	CARGO	Tecnico de Negócios	Tecnico de Negócios	t	f
137	CARGO	Tecnico de Redes	Tecnico de Redes	t	f
138	CARGO	Tecnico de Suporte	Tecnico de Suporte	t	f
139	CARGO	Trainee	Trainee	t	f
140	CARGO	Ux / Ui Design	Ux / Ui Design	t	f
141	VINCULO	CLT	CLT	t	f
142	VINCULO	PJ	PJ	t	f
143	VINCULO	Freelancer	Freelancer	t	f
144	VINCULO	Consultor	Consultor	t	f
145	VINCULO	Estágio	Estágio	t	f
146	VINCULO	Aprendiz	Aprendiz	t	f
147	MODALIDADE	Presencial	Presencial	t	f
148	MODALIDADE	Híbrido	Híbrido	t	f
149	MODALIDADE	Remoto	Remoto	t	f
150	SENIORIDADE	Jovem Aprendiz	Jovem Aprendiz	t	f
151	SENIORIDADE	Estagiário	Estagiário	t	f
152	SENIORIDADE	Trainee	Trainee	t	f
153	SENIORIDADE	Júnior	Júnior	t	f
154	SENIORIDADE	Pleno	Pleno	t	f
155	SENIORIDADE	Sênior	Sênior	t	f
156	SENIORIDADE	Master	Master	t	f
157	SENIORIDADE	Especialista	Especialista	t	f
158	STEP	l	Step l	t	f
159	STEP	ll	Step ll	t	f
160	STEP	lll	Step lll	t	f
161	STEP	IV	Step lV	t	f
162	STEP	V	Step V	t	f
163	TIPO_SERVICO	Desenvolvimento	Desenvolvimento	t	f
164	TIPO_SERVICO	Sustentação	Sustentação	t	f
165	TIPO_SERVICO	Suporte	Suporte	t	f
166	TIPO_SERVICO	Consultoria	Consultoria	t	f
167	TIPO_SERVICO	Apoio	Apoio	t	f
168	AREA_TECNOLOGIA	Arquitetura	Arquitetura	t	f
169	AREA_TECNOLOGIA	Back-End	Back-End	t	f
170	AREA_TECNOLOGIA	Banco de Dados	Banco de Dados	t	f
171	AREA_TECNOLOGIA	Design de Sistemas	Design de Sistemas	t	f
172	AREA_TECNOLOGIA	DevOps 	DevOps 	t	f
173	AREA_TECNOLOGIA	Front-End	Front-End	t	f
174	AREA_TECNOLOGIA	Infraestrutura	Infraestrutura	t	f
175	AREA_TECNOLOGIA	Qualidade e Testes de Sistemas	Qualidade e Testes de Sistemas	t	f
176	AREA_TECNOLOGIA	Requisitos de Sistemas	Requisitos de Sistemas	t	f
177	AREA_TECNOLOGIA	Segurança	Segurança	t	f
178	MOTIVO_AUSENCIA	Feriado	Feriado	t	f
179	MOTIVO_AUSENCIA	Férias	Férias	t	f
180	MOTIVO_AUSENCIA	Banco de Horas	Banco de Horas	t	f
181	MOTIVO_AUSENCIA	Day Off	Day Off	t	f
182	MOTIVO_AUSENCIA	Falta	Falta	t	f
183	MOTIVO_AUSENCIA	Saúde	Saúde	t	f
184	MOTIVO_AUSENCIA	Licença Maternidade	Licença Maternidade	t	f
185	MOTIVO_AUSENCIA	Licença Paternidade	Licença Paternidade	t	f
186	MOTIVO_AUSENCIA	Casamento	Casamento	t	f
187	MOTIVO_AUSENCIA	Óbito	Óbito	t	f
188	MOTIVO_AUSENCIA	Doação Sangue	Doação Sangue	t	f
189	MOTIVO_AUSENCIA	Alistamento Eleitoral	Alistamento Eleitoral	t	f
190	MOTIVO_AUSENCIA	Serviço Militar	Serviço Militar	t	f
191	MOTIVO_AUSENCIA	Vestibular	Vestibular	t	f
192	MOTIVO_AUSENCIA	Comparecimento Juízo	Comparecimento Juízo	t	f
193	MOTIVO_AUSENCIA	Representação Sindical	Representação Sindical	t	f
194	MOTIVO_AUSENCIA	Licença Remunerada	Licença Remunerada	t	f
195	STATUS_AUSENCIA	Planejado	Planejado	t	f
196	STATUS_AUSENCIA	Gozado	Gozado	t	f
197	STATUS_AUSENCIA	Utilizado	Utilizado	t	f
198	TIPO_MUDANCA_SITUACAO	Promoção	Promoção	t	f
199	TIPO_MUDANCA_SITUACAO	Benefício	Benefício	t	f
200	TIPO_MUDANCA_SITUACAO	Salário	Salário	t	f
201	TIPO_MUDANCA_SITUACAO	Função Temporária	Função Temporária	t	f
202	TIPO_MUDANCA_SITUACAO	Bônus	Bônus	t	f
203	TIPO_MUDANCA_SITUACAO	Mudança Cargo	Mudança Cargo	t	f
204	TIPO_MUDANCA_SITUACAO	Mudança Horário	Mudança Horário	t	f
205	TIPO_MUDANCA_SITUACAO	Reajuste Cct	Reajuste Cct	t	f
206	TIPO_MUDANCA_SITUACAO	Enquadramento PCCR	Enquadramento PCCR	t	f
207	TIPO_MUDANCA_SITUACAO	Mudança Lotação Obra	Mudança de Lotação na Obra	t	f
208	SITUACAO_DEMANDA	Concluida	Demanda Concluída	t	f
209	SITUACAO_DEMANDA	Em Desenvolvimento	Demanda Em Desenvolvimento	t	f
210	SITUACAO_DEMANDA	Planejada	Demanda Planejada	t	f
211	SITUACAO_DEMANDA	Atrasada	Demanda Atrasada	t	f
212	SITUACAO_RELEASE	Concluída	Concluída	t	f
213	SITUACAO_RELEASE	Em Desenvolvimento	Release Em Desenvolvimento	t	f
214	SITUACAO_RELEASE	Planejada	Release Planejada	t	f
215	SITUACAO_RELEASE	Atrasada	Atrasada	t	f
216	SITUACAO_CONTRATO	Ativo	Contrato Ativo	t	f
217	SITUACAO_CONTRATO	Vencido	Contrato Vencido	t	f
218	SITUACAO_CONTRATO	Suspenso	Contrato Suspenso	t	f
219	SITUACAO_CONTRATACOES	Aprovado	Contratação Aprovada	t	f
220	SITUACAO_CONTRATACOES	Finalizado	Contratação Finalizada	t	f
221	SITUACAO_AUSENCIA	Pendente	Pendente	t	f
222	SITUACAO_AUSENCIA	Aprovado	Aprovado	t	f
223	SITUACAO_AUSENCIA	Rejeitado	Rejeitado	t	f
224	SITUACAO_ADITIVO	Ativo	Aditivo Ativo	t	f
225	SITUACAO_ADITIVO	Vencido	Aditivo Vencido	t	f
226	TIPO_DEMANDA	Melhoria	Melhoria	t	f
227	TIPO_DEMANDA	Desenvolvimento	Desenvolvimento	t	f
228	TIPO_DEMANDA	Sustentação	Sustentação	t	f
229	TIPO_DEMANDA	Outsourcing	Outsourcing	t	f
230	TIPO_DEMANDA	Suporte	Suporte	t	f
231	METODOLOGIA	Scrum	Scrum	t	f
232	METODOLOGIA	Kanban	Kanban	t	f
233	METODOLOGIA	Waterfall	Waterfall	t	f
234	METODOLOGIA	XP	Xp - Extreme Programming	t	f
235	METODOLOGIA	Lean	Lean	t	f
236	METODOLOGIA	Safe	Safe - Scaled Agile Framework	t	f
237	METODOLOGIA	Híbrido	Híbrido	t	f
238	SITUACAO_CONTRATO	Cancelado	Contrato Cancelado	t	f
239	SITUACAO_CONTRATO	A Renovar	Contrato A Renovar	t	f
240	NIVEL_IMPORTANCIA	Obrigatório	Nível de Importância Obrigatório	t	f
241	NIVEL_IMPORTANCIA	Desejável	Nível de Importância Desejável	t	f
242	SITUACAO_SOLICITACAO_PROFISSIONAL	Suspensa	Suspensa	t	f
243	SITUACAO_SOLICITACAO_PROFISSIONAL	Atendida No DLV	Atendida No DLV	t	f
244	SITUACAO_SOLICITACAO_PROFISSIONAL	Encaminhada G&C	Encaminhada G&C	t	f
245	SITUACAO_SOLICITACAO_PROFISSIONAL	Atendida Pelo G&C	Atendida Pelo G&C	t	f
246	SITUACAO_SOLICITACAO_PROFISSIONAL	Cancelada	Cancelada	t	f
247	SITUACAO_FERIAS	Planejado	Planejada	t	f
248	SITUACAO_FERIAS	Em Andamento	Férias Em Andamento	t	f
249	SITUACAO_FERIAS	Concluído	Férias Concluídas	t	f
250	SITUACAO_FERIAS	Vencido	Férias Com Prazo Vencido	t	f
251	STATUS_FATURAMENTO	Ativo	Faturamento Ativo	t	f
252	STATUS_FATURAMENTO	Inativo	Faturamento Inativo	t	f
253	STATUS_PAGAMENTO	Pendente	Pagamento Ainda Não Realizado	t	f
254	STATUS_PAGAMENTO	Pago	Pagamento Realizado	t	f
255	STATUS_PAGAMENTO	Em Atraso	Pagamento Em Atraso	t	f
256	STATUS_PAGAMENTO	Cancelado	Pagamento Cancelado	t	f
257	SITUACAO_PROFISSIONAL	Suspensa	Suspensa	t	f
258	SITUACAO_PROFISSIONAL	Aprovada	Aprovado	t	f
259	SITUACAO_PROFISSIONAL	Em Análise	Em Análise	t	f
260	SITUACAO_PROFISSIONAL	Pendente	Pendente	t	f
261	SITUACAO_PROFISSIONAL	Rejeitada	Rejeitada	t	f
262	SITUACAO_SOLICITACAO_PROFISSIONAL	Aberta	Aberta	t	f
263	SITUACAO_SOLICITACAO_PROFISSIONAL	Em Andamento	Em Andamento	t	f
264	SITUACAO_AUSENCIA	Concluído 	Concluído 	t	f
265	CENTRO_CUSTO	Centro de custo 265	Centro de custo 265	t	t
266	CENTRO_CUSTO	Centro de custo 266	Centro de custo 266	t	t
267	CENTRO_CUSTO	Centro de custo 267	Centro de custo 267	t	t
268	CENTRO_CUSTO	Centro de custo 268	Centro de custo 268	t	t
269	CENTRO_CUSTO	Centro de custo 269	Centro de custo 269	t	t
270	CENTRO_CUSTO	Centro de custo 270	Centro de custo 270	t	t
271	CENTRO_CUSTO	Centro de custo 271	Centro de custo 271	t	f
272	CENTRO_CUSTO	Centro de custo 272	Centro de custo 272	t	t
273	CENTRO_CUSTO	Centro de custo 273	Centro de custo 273	t	t
274	CENTRO_CUSTO	Centro de custo 274	Centro de custo 274	t	f
275	TIPO_SERVICO	Outsourcing	Outsourcing	t	f
277	CENTRO_CUSTO	Centro de custo 277	Centro de custo 277	t	f
278	CENTRO_CUSTO	Centro de custo 278	Centro de custo 278	t	f
279	CENTRO_CUSTO	Centro de custo 279	Centro de custo 279	t	f
280	ANDAMENTO_DEMANDA	Em Atenção	Demanda que exige acompanhamento ou atenção especial.	t	f
281	ANDAMENTO_DEMANDA	Concluída	Demanda concluída.	t	f
282	ANDAMENTO_DEMANDA	Iniciada	Demanda iniciada.	t	f
283	ANDAMENTO_DEMANDA	Não Iniciada	Demanda ainda não iniciada.	t	f
284	ANDAMENTO_DEMANDA	Em Desenvolvimento	Demanda em desenvolvimento.	t	f
285	ANDAMENTO_DEMANDA	Crítica	Demanda em andamento crítico.	t	f
286	HISTORICO_ENTIDADE	Releases	Entidade de releases utilizada na tabela geral de histórico de alterações.	t	f
287	CENTRO_CUSTO	Centro de custo 287	Centro de custo 287	t	f
288	HISTORICO_ENTIDADE	Colaboradores	Entidade de colaboradores utilizada na tabela geral de histórico de alterações.	t	f
289	HISTORICO_ENTIDADE	Contratos	Entidade de contratos utilizada na tabela geral de histórico de alterações.	t	f
290	HISTORICO_ENTIDADE	Hierarquia Organizacional	Entidade de hierarquia organizacional utilizada na tabela geral de histórico de alterações.	t	f
291	HISTORICO_ENTIDADE	LNC	Entidade LNC utilizada na tabela geral de histórico de alterações.	t	f
292	STATUS_CURSO	Pendente	Curso registrado no LNC, aguardando início.	t	f
293	STATUS_CURSO	Em Progresso	Curso em execução pelo colaborador.	t	f
294	STATUS_CURSO	Concluído	Curso finalizado e certificado anexado.	t	f
295	STATUS_CURSO	Pausado	Curso Pausado ou não realizado pelo colaborador.	t	f
296	SETOR_EMPRESA	DSO	DSO	t	f
297	SETOR_EMPRESA	CDS	CDS	t	f
298	SETOR_EMPRESA	CAS	CAS	t	f
299	SETOR_EMPRESA	INFRA	INFRA	t	f
300	SETOR_EMPRESA	TGI	TGI	t	f
301	SETOR_EMPRESA	COMERCIAL	COMERCIAL	t	f
302	SETOR_EMPRESA	EDO	EDO	t	f
303	SITUACAO_CONTRATO	Encerrado	Contrato Encerrado	t	f
304	SITUACAO_CONTRATO	Autorizado	Contrato Autorizado	t	f
305	CATEGORIA_CERTIFICADO	Curso Complementar	Curso Complementar	t	f
306	CATEGORIA_CERTIFICADO	Graduação	Graduação	t	f
307	CATEGORIA_CERTIFICADO	Pós-graduação/MBA	Pós-graduação/MBA	t	f
308	CATEGORIA_CERTIFICADO	Certificado Profissional	Certificado Profissional	t	f
309	GRUPO	Projetos	Projetos	t	f
310	GRUPO	Investimento	Investimento	t	f
311	GRUPO	Overhead	Overhead	t	f
312	GRUPO	Parceiros	Parceiros	t	f
313	HISTORICO_ENTIDADE	Produtos	Histórico de Produtos	t	f
314	STATUS_ESCOPO_PRODUTO	Adiado	Item adiado	t	f
315	STATUS_ESCOPO_PRODUTO	Em Progresso	Item em progresso	t	f
316	STATUS_ESCOPO_PRODUTO	Concluído	Item concluído	t	f
317	STATUS_ESCOPO_PRODUTO	Pendente	Item pendente	t	f
318	NIVEL_CONHECIMENTO	BASICO	BASICO	t	f
319	AREA_TECNOLOGIA	Desenvolvimento legado	Desenvolvimento legado	t	f
320	NIVEL_CONHECIMENTO	INTERMEDIARIO	INTERMEDIARIO	t	f
321	NIVEL_CONHECIMENTO	AVANCADO	AVANCADO	t	f
\.


--
-- TOC entry 3637 (class 0 OID 95827)
-- Dependencies: 239
-- Data for Name: planejamentos; Type: TABLE DATA; Schema: InHire; Owner: postgres
--

COPY "InHire".planejamentos (id, id_alocacao, mes, ano, porcentagem, status, deletado) FROM stdin;
1	1	Dez	2025	100	t	f
2	2	Dez	2025	100	t	f
3	3	Dez	2025	100	t	f
4	5	Dez	2025	100	t	f
5	6	Dez	2025	100	t	f
6	7	Dez	2025	100	t	f
8	9	Dez	2025	100	t	f
9	10	Dez	2025	100	t	f
10	11	Dez	2025	100	t	f
11	12	Dez	2025	100	t	f
12	13	Dez	2025	100	t	f
14	15	Dez	2025	100	t	f
15	16	Dez	2025	100	t	f
16	17	Dez	2025	100	t	f
17	19	Dez	2025	100	t	f
18	20	Dez	2025	100	t	f
19	21	Dez	2025	100	t	f
20	22	Dez	2025	100	t	f
21	23	Dez	2025	100	t	f
22	24	Dez	2025	100	t	f
23	25	Dez	2025	100	t	f
24	26	Dez	2025	100	t	f
26	28	Dez	2025	100	t	f
28	30	Dez	2025	100	t	f
29	31	Dez	2025	100	t	f
30	32	Dez	2025	100	t	f
31	33	Dez	2025	100	t	f
32	35	Dez	2025	100	t	f
33	36	Dez	2025	100	t	f
34	37	Dez	2025	100	t	f
36	39	Dez	2025	100	t	f
37	40	Dez	2025	100	t	f
38	41	Dez	2025	100	t	f
39	42	Dez	2025	100	t	f
40	43	Dez	2025	100	t	f
41	44	Dez	2025	100	t	f
42	45	Dez	2025	100	t	f
43	46	Dez	2025	100	t	f
45	48	Dez	2025	100	t	f
46	49	Dez	2025	100	t	f
47	50	Dez	2025	100	t	f
48	51	Dez	2025	100	t	f
49	52	Dez	2025	100	t	f
50	53	Dez	2025	100	t	f
51	54	Dez	2025	100	t	f
52	55	Dez	2025	100	t	f
53	57	Dez	2025	100	t	f
54	58	Dez	2025	100	t	f
55	59	Dez	2025	100	t	f
56	60	Dez	2025	20	t	f
57	61	Dez	2025	100	t	f
58	64	Dez	2025	100	t	f
59	65	Dez	2025	100	t	f
60	66	Dez	2025	100	t	f
61	67	Dez	2025	100	t	f
62	68	Dez	2025	100	t	f
64	70	Dez	2025	100	t	f
65	71	Dez	2025	100	t	f
66	72	Dez	2025	100	t	f
67	73	Dez	2025	100	t	f
68	74	Dez	2025	100	t	f
70	76	Dez	2025	100	t	f
71	77	Dez	2025	100	t	f
72	78	Dez	2025	100	t	f
73	79	Dez	2025	100	t	f
75	81	Dez	2025	100	t	f
76	82	Dez	2025	100	t	f
77	83	Dez	2025	100	t	f
78	84	Dez	2025	100	t	f
79	85	Dez	2025	100	t	f
80	86	Dez	2025	100	t	f
81	87	Dez	2025	100	t	f
82	88	Dez	2025	100	t	f
84	90	Dez	2025	100	t	f
85	91	Dez	2025	100	t	f
86	93	Dez	2025	100	t	f
87	94	Dez	2025	100	t	f
88	95	Dez	2025	100	t	f
89	96	Dez	2025	100	t	f
90	97	Dez	2025	100	t	f
91	98	Dez	2025	100	t	f
92	99	Dez	2025	100	t	f
93	100	Dez	2025	100	t	f
94	101	Dez	2025	100	t	f
95	102	Dez	2025	100	t	f
96	103	Dez	2025	100	t	f
97	104	Dez	2025	100	t	f
98	105	Dez	2025	100	t	f
99	106	Dez	2025	100	t	f
100	107	Dez	2025	100	t	f
102	109	Dez	2025	100	t	f
103	110	Dez	2025	100	t	f
104	111	Dez	2025	100	t	f
105	112	Dez	2025	100	t	f
106	113	Dez	2025	100	t	f
107	114	Dez	2025	100	t	f
108	115	Dez	2025	100	t	f
109	116	Dez	2025	100	t	f
110	117	Dez	2025	100	t	f
111	118	Dez	2025	100	t	f
112	119	Dez	2025	100	t	f
113	120	Dez	2025	100	t	f
114	121	Dez	2025	100	t	f
115	122	Dez	2025	100	t	f
116	123	Dez	2025	100	t	f
117	124	Dez	2025	100	t	f
118	125	Dez	2025	100	t	f
119	126	Dez	2025	100	t	f
121	128	Dez	2025	100	t	f
122	129	Dez	2025	100	t	f
124	131	Dez	2025	100	t	f
125	132	Dez	2025	100	t	f
126	133	Dez	2025	100	t	f
127	134	Dez	2025	100	t	f
128	135	Dez	2025	100	t	f
129	136	Dez	2025	100	t	f
130	137	Dez	2025	100	t	f
131	138	Dez	2025	100	t	f
132	139	Dez	2025	100	t	f
133	141	Dez	2025	100	t	f
134	142	Dez	2025	100	t	f
135	143	Dez	2025	100	t	f
136	144	Dez	2025	100	t	f
138	146	Dez	2025	100	t	f
139	147	Dez	2025	100	t	f
140	148	Dez	2025	100	t	f
141	149	Dez	2025	100	t	f
142	150	Dez	2025	100	t	f
143	151	Dez	2025	100	t	f
145	153	Dez	2025	100	t	f
146	154	Dez	2025	100	t	f
147	155	Dez	2025	100	t	f
150	158	Dez	2025	100	t	f
151	159	Dez	2025	100	t	f
152	160	Dez	2025	100	t	f
154	162	Dez	2025	100	t	f
155	163	Dez	2025	100	t	f
156	164	Dez	2025	100	t	f
157	165	Dez	2025	100	t	f
158	166	Dez	2025	100	t	f
159	1	Jan	2026	100	t	f
160	2	Jan	2026	100	t	f
161	3	Jan	2026	100	t	f
162	5	Jan	2026	100	t	f
163	6	Jan	2026	100	t	f
164	7	Jan	2026	100	t	f
166	9	Jan	2026	100	t	f
167	10	Jan	2026	100	t	f
168	11	Jan	2026	100	t	f
169	12	Jan	2026	100	t	f
170	13	Jan	2026	100	t	f
172	15	Jan	2026	100	t	f
173	16	Jan	2026	100	t	f
174	17	Jan	2026	100	t	f
175	19	Jan	2026	100	t	f
176	20	Jan	2026	100	t	f
177	21	Jan	2026	100	t	f
178	22	Jan	2026	100	t	f
179	23	Jan	2026	100	t	f
180	24	Jan	2026	100	t	f
181	25	Jan	2026	100	t	f
182	26	Jan	2026	100	t	f
184	28	Jan	2026	100	t	f
186	30	Jan	2026	100	t	f
187	31	Jan	2026	100	t	f
188	32	Jan	2026	100	t	f
189	33	Jan	2026	100	t	f
190	35	Jan	2026	100	t	f
191	36	Jan	2026	100	t	f
192	37	Jan	2026	100	t	f
194	39	Jan	2026	100	t	f
195	40	Jan	2026	100	t	f
196	41	Jan	2026	100	t	f
197	42	Jan	2026	100	t	f
198	43	Jan	2026	100	t	f
199	44	Jan	2026	100	t	f
200	45	Jan	2026	100	t	f
201	46	Jan	2026	100	t	f
203	48	Jan	2026	100	t	f
204	49	Jan	2026	100	t	f
205	50	Jan	2026	100	t	f
206	51	Jan	2026	100	t	f
207	52	Jan	2026	100	t	f
208	53	Jan	2026	100	t	f
209	54	Jan	2026	100	t	f
210	55	Jan	2026	100	t	f
211	57	Jan	2026	100	t	f
212	58	Jan	2026	100	t	f
213	59	Jan	2026	100	t	f
214	60	Jan	2026	20	t	f
215	61	Jan	2026	100	t	f
216	64	Jan	2026	100	t	f
217	65	Jan	2026	100	t	f
218	66	Jan	2026	100	t	f
219	67	Jan	2026	100	t	f
220	68	Jan	2026	100	t	f
222	70	Jan	2026	100	t	f
223	71	Jan	2026	100	t	f
224	72	Jan	2026	100	t	f
225	73	Jan	2026	100	t	f
226	74	Jan	2026	100	t	f
228	76	Jan	2026	100	t	f
229	77	Jan	2026	100	t	f
230	78	Jan	2026	100	t	f
231	79	Jan	2026	100	t	f
233	81	Jan	2026	100	t	f
234	82	Jan	2026	100	t	f
235	83	Jan	2026	100	t	f
236	84	Jan	2026	100	t	f
237	85	Jan	2026	100	t	f
238	86	Jan	2026	100	t	f
239	87	Jan	2026	100	t	f
240	88	Jan	2026	100	t	f
242	90	Jan	2026	100	t	f
243	91	Jan	2026	100	t	f
244	93	Jan	2026	100	t	f
245	94	Jan	2026	100	t	f
246	95	Jan	2026	100	t	f
247	96	Jan	2026	100	t	f
248	97	Jan	2026	100	t	f
249	98	Jan	2026	100	t	f
250	99	Jan	2026	100	t	f
251	100	Jan	2026	100	t	f
252	101	Jan	2026	100	t	f
253	102	Jan	2026	100	t	f
254	103	Jan	2026	100	t	f
255	104	Jan	2026	100	t	f
256	105	Jan	2026	100	t	f
257	106	Jan	2026	100	t	f
258	107	Jan	2026	100	t	f
260	109	Jan	2026	100	t	f
261	110	Jan	2026	100	t	f
262	111	Jan	2026	100	t	f
263	112	Jan	2026	100	t	f
264	113	Jan	2026	100	t	f
265	114	Jan	2026	100	t	f
266	115	Jan	2026	100	t	f
267	116	Jan	2026	100	t	f
268	117	Jan	2026	100	t	f
269	118	Jan	2026	100	t	f
270	119	Jan	2026	100	t	f
271	120	Jan	2026	100	t	f
272	121	Jan	2026	100	t	f
273	122	Jan	2026	100	t	f
274	123	Jan	2026	100	t	f
275	124	Jan	2026	100	t	f
276	125	Jan	2026	100	t	f
277	126	Jan	2026	100	t	f
279	128	Jan	2026	100	t	f
280	129	Jan	2026	100	t	f
282	131	Jan	2026	100	t	f
283	132	Jan	2026	100	t	f
284	133	Jan	2026	100	t	f
285	134	Jan	2026	100	t	f
286	135	Jan	2026	100	t	f
287	136	Jan	2026	100	t	f
288	137	Jan	2026	100	t	f
289	138	Jan	2026	100	t	f
290	139	Jan	2026	100	t	f
291	141	Jan	2026	100	t	f
292	142	Jan	2026	100	t	f
293	143	Jan	2026	100	t	f
294	144	Jan	2026	100	t	f
296	146	Jan	2026	100	t	f
297	147	Jan	2026	100	t	f
298	148	Jan	2026	100	t	f
299	149	Jan	2026	100	t	f
300	150	Jan	2026	100	t	f
301	151	Jan	2026	100	t	f
303	153	Jan	2026	100	t	f
304	154	Jan	2026	100	t	f
305	155	Jan	2026	100	t	f
308	158	Jan	2026	100	t	f
309	159	Jan	2026	100	t	f
310	160	Jan	2026	100	t	f
312	162	Jan	2026	100	t	f
313	163	Jan	2026	100	t	f
314	164	Jan	2026	100	t	f
315	165	Jan	2026	100	t	f
316	166	Jan	2026	100	t	f
317	1	Fev	2026	100	t	f
318	2	Fev	2026	100	t	f
319	3	Fev	2026	100	t	f
320	5	Fev	2026	100	t	f
321	6	Fev	2026	100	t	f
322	7	Fev	2026	100	t	f
324	9	Fev	2026	100	t	f
325	10	Fev	2026	100	t	f
326	11	Fev	2026	100	t	f
327	12	Fev	2026	100	t	f
328	13	Fev	2026	100	t	f
330	15	Fev	2026	100	t	f
331	16	Fev	2026	100	t	f
332	17	Fev	2026	100	t	f
333	19	Fev	2026	100	t	f
334	20	Fev	2026	100	t	f
335	21	Fev	2026	100	t	f
336	22	Fev	2026	100	t	f
337	23	Fev	2026	100	t	f
338	24	Fev	2026	100	t	f
339	25	Fev	2026	100	t	f
340	26	Fev	2026	100	t	f
342	28	Fev	2026	100	t	f
344	30	Fev	2026	100	t	f
345	31	Fev	2026	100	t	f
346	32	Fev	2026	100	t	f
347	33	Fev	2026	100	t	f
348	35	Fev	2026	100	t	f
349	36	Fev	2026	100	t	f
350	37	Fev	2026	100	t	f
352	39	Fev	2026	100	t	f
353	40	Fev	2026	100	t	f
354	41	Fev	2026	100	t	f
355	42	Fev	2026	100	t	f
356	43	Fev	2026	100	t	f
357	44	Fev	2026	100	t	f
358	45	Fev	2026	100	t	f
359	46	Fev	2026	100	t	f
361	48	Fev	2026	100	t	f
362	49	Fev	2026	100	t	f
363	50	Fev	2026	100	t	f
364	51	Fev	2026	100	t	f
365	52	Fev	2026	100	t	f
366	53	Fev	2026	100	t	f
367	54	Fev	2026	100	t	f
368	55	Fev	2026	100	t	f
369	57	Fev	2026	100	t	f
370	58	Fev	2026	100	t	f
371	59	Fev	2026	100	t	f
372	60	Fev	2026	5	t	f
373	61	Fev	2026	100	t	f
374	64	Fev	2026	100	t	f
375	65	Fev	2026	100	t	f
376	66	Fev	2026	100	t	f
377	67	Fev	2026	100	t	f
378	68	Fev	2026	100	t	f
380	70	Fev	2026	100	t	f
381	71	Fev	2026	100	t	f
382	72	Fev	2026	100	t	f
383	73	Fev	2026	100	t	f
384	74	Fev	2026	100	t	f
386	76	Fev	2026	100	t	f
387	77	Fev	2026	100	t	f
388	78	Fev	2026	100	t	f
389	79	Fev	2026	100	t	f
391	81	Fev	2026	100	t	f
392	82	Fev	2026	100	t	f
393	83	Fev	2026	100	t	f
394	84	Fev	2026	100	t	f
395	85	Fev	2026	100	t	f
396	86	Fev	2026	100	t	f
397	87	Fev	2026	100	t	f
398	88	Fev	2026	100	t	f
400	90	Fev	2026	100	t	f
401	91	Fev	2026	100	t	f
402	93	Fev	2026	100	t	f
403	94	Fev	2026	100	t	f
404	95	Fev	2026	100	t	f
405	96	Fev	2026	100	t	f
406	97	Fev	2026	100	t	f
407	98	Fev	2026	100	t	f
408	99	Fev	2026	100	t	f
409	100	Fev	2026	0	t	f
410	101	Fev	2026	100	t	f
411	102	Fev	2026	100	t	f
412	103	Fev	2026	100	t	f
413	104	Fev	2026	100	t	f
414	105	Fev	2026	100	t	f
415	106	Fev	2026	100	t	f
416	107	Fev	2026	100	t	f
418	109	Fev	2026	100	t	f
419	110	Fev	2026	100	t	f
420	111	Fev	2026	100	t	f
421	112	Fev	2026	100	t	f
422	113	Fev	2026	0	t	f
423	114	Fev	2026	100	t	f
424	115	Fev	2026	100	t	f
425	116	Fev	2026	100	t	f
426	117	Fev	2026	100	t	f
427	118	Fev	2026	100	t	f
428	119	Fev	2026	100	t	f
429	120	Fev	2026	100	t	f
430	121	Fev	2026	100	t	f
431	122	Fev	2026	100	t	f
432	123	Fev	2026	100	t	f
433	124	Fev	2026	100	t	f
434	125	Fev	2026	100	t	f
435	126	Fev	2026	100	t	f
437	128	Fev	2026	100	t	f
438	129	Fev	2026	100	t	f
440	131	Fev	2026	100	t	f
441	132	Fev	2026	100	t	f
442	133	Fev	2026	100	t	f
443	134	Fev	2026	100	t	f
444	135	Fev	2026	100	t	f
445	136	Fev	2026	100	t	f
446	137	Fev	2026	100	t	f
447	138	Fev	2026	100	t	f
448	139	Fev	2026	100	t	f
449	141	Fev	2026	100	t	f
450	142	Fev	2026	100	t	f
451	143	Fev	2026	100	t	f
452	144	Fev	2026	100	t	f
454	146	Fev	2026	100	t	f
455	147	Fev	2026	100	t	f
456	148	Fev	2026	100	t	f
457	149	Fev	2026	100	t	f
458	150	Fev	2026	100	t	f
459	151	Fev	2026	100	t	f
461	153	Fev	2026	100	t	f
462	154	Fev	2026	100	t	f
463	155	Fev	2026	100	t	f
466	158	Fev	2026	100	t	f
467	159	Fev	2026	100	t	f
468	160	Fev	2026	100	t	f
470	162	Fev	2026	100	t	f
471	163	Fev	2026	100	t	f
472	164	Fev	2026	100	t	f
473	165	Fev	2026	100	t	f
474	166	Fev	2026	100	t	f
475	1	Mar	2026	100	t	f
476	2	Mar	2026	100	t	f
477	3	Mar	2026	100	t	f
478	5	Mar	2026	100	t	f
479	6	Mar	2026	100	t	f
480	7	Mar	2026	100	t	f
482	9	Mar	2026	100	t	f
483	10	Mar	2026	100	t	f
484	11	Mar	2026	100	t	f
485	12	Mar	2026	100	t	f
486	13	Mar	2026	100	t	f
488	15	Mar	2026	100	t	f
489	16	Mar	2026	100	t	f
490	17	Mar	2026	100	t	f
491	19	Mar	2026	100	t	f
492	20	Mar	2026	100	t	f
493	21	Mar	2026	100	t	f
494	22	Mar	2026	100	t	f
495	23	Mar	2026	50	t	f
496	24	Mar	2026	100	t	f
497	25	Mar	2026	100	t	f
498	26	Mar	2026	100	t	f
500	28	Mar	2026	100	t	f
502	30	Mar	2026	100	t	f
503	31	Mar	2026	100	t	f
504	32	Mar	2026	100	t	f
505	33	Mar	2026	100	t	f
506	35	Mar	2026	100	t	f
507	36	Mar	2026	100	t	f
508	37	Mar	2026	100	t	f
510	39	Mar	2026	100	t	f
511	40	Mar	2026	100	t	f
512	41	Mar	2026	100	t	f
513	42	Mar	2026	100	t	f
514	43	Mar	2026	100	t	f
515	44	Mar	2026	100	t	f
516	45	Mar	2026	100	t	f
517	46	Mar	2026	100	t	f
519	48	Mar	2026	100	t	f
520	49	Mar	2026	100	t	f
521	50	Mar	2026	100	t	f
522	51	Mar	2026	100	t	f
523	52	Mar	2026	100	t	f
524	53	Mar	2026	100	t	f
525	54	Mar	2026	100	t	f
526	55	Mar	2026	100	t	f
527	57	Mar	2026	100	t	f
528	58	Mar	2026	100	t	f
529	59	Mar	2026	100	t	f
530	60	Mar	2026	100	t	f
531	61	Mar	2026	100	t	f
532	64	Mar	2026	100	t	f
533	65	Mar	2026	100	t	f
534	66	Mar	2026	100	t	f
535	67	Mar	2026	100	t	f
536	68	Mar	2026	100	t	f
538	70	Mar	2026	100	t	f
539	71	Mar	2026	100	t	f
540	72	Mar	2026	100	t	f
541	73	Mar	2026	100	t	f
542	74	Mar	2026	100	t	f
544	76	Mar	2026	100	t	f
545	77	Mar	2026	100	t	f
546	78	Mar	2026	100	t	f
547	79	Mar	2026	100	t	f
549	81	Mar	2026	100	t	f
550	82	Mar	2026	100	t	f
551	83	Mar	2026	100	t	f
552	84	Mar	2026	100	t	f
553	85	Mar	2026	100	t	f
554	86	Mar	2026	100	t	f
555	87	Mar	2026	100	t	f
556	88	Mar	2026	100	t	f
558	90	Mar	2026	100	t	f
559	91	Mar	2026	100	t	f
560	93	Mar	2026	100	t	f
561	94	Mar	2026	100	t	f
562	95	Mar	2026	100	t	f
563	96	Mar	2026	100	t	f
564	97	Mar	2026	100	t	f
565	98	Mar	2026	100	t	f
566	99	Mar	2026	100	t	f
567	100	Mar	2026	0	t	f
568	101	Mar	2026	100	t	f
569	102	Mar	2026	100	t	f
570	103	Mar	2026	100	t	f
571	104	Mar	2026	100	t	f
572	105	Mar	2026	100	t	f
573	106	Mar	2026	100	t	f
574	107	Mar	2026	100	t	f
576	109	Mar	2026	100	t	f
577	110	Mar	2026	100	t	f
578	111	Mar	2026	100	t	f
579	112	Mar	2026	100	t	f
580	113	Mar	2026	0	t	f
581	114	Mar	2026	100	t	f
582	115	Mar	2026	100	t	f
583	116	Mar	2026	100	t	f
584	117	Mar	2026	100	t	f
585	118	Mar	2026	100	t	f
586	119	Mar	2026	100	t	f
587	120	Mar	2026	100	t	f
588	121	Mar	2026	100	t	f
589	122	Mar	2026	100	t	f
590	123	Mar	2026	100	t	f
591	124	Mar	2026	100	t	f
592	125	Mar	2026	100	t	f
593	126	Mar	2026	100	t	f
595	128	Mar	2026	100	t	f
596	129	Mar	2026	100	t	f
598	131	Mar	2026	100	t	f
599	132	Mar	2026	100	t	f
600	133	Mar	2026	100	t	f
601	134	Mar	2026	100	t	f
602	135	Mar	2026	0	t	f
603	136	Mar	2026	100	t	f
604	137	Mar	2026	100	t	f
605	138	Mar	2026	100	t	f
606	139	Mar	2026	100	t	f
607	141	Mar	2026	100	t	f
608	142	Mar	2026	100	t	f
609	143	Mar	2026	100	t	f
610	144	Mar	2026	100	t	f
612	146	Mar	2026	100	t	f
613	147	Mar	2026	100	t	f
614	148	Mar	2026	100	t	f
615	149	Mar	2026	100	t	f
616	150	Mar	2026	100	t	f
617	151	Mar	2026	100	t	f
619	153	Mar	2026	100	t	f
620	154	Mar	2026	100	t	f
621	155	Mar	2026	100	t	f
624	158	Mar	2026	100	t	f
625	159	Mar	2026	100	t	f
626	160	Mar	2026	100	t	f
628	162	Mar	2026	100	t	f
629	163	Mar	2026	100	t	f
630	164	Mar	2026	100	t	f
631	165	Mar	2026	100	t	f
632	166	Mar	2026	100	t	f
633	1	Abr	2026	100	t	f
634	2	Abr	2026	100	t	f
635	3	Abr	2026	100	t	f
636	5	Abr	2026	100	t	f
637	6	Abr	2026	100	t	f
638	7	Abr	2026	100	t	f
640	9	Abr	2026	100	t	f
641	10	Abr	2026	100	t	f
642	11	Abr	2026	100	t	f
643	12	Abr	2026	100	t	f
644	13	Abr	2026	100	t	f
646	15	Abr	2026	100	t	f
647	16	Abr	2026	100	t	f
648	17	Abr	2026	100	t	f
649	19	Abr	2026	100	t	f
650	20	Abr	2026	100	t	f
651	21	Abr	2026	100	t	f
652	22	Abr	2026	100	t	f
653	23	Abr	2026	50	t	f
654	24	Abr	2026	100	t	f
655	25	Abr	2026	100	t	f
656	26	Abr	2026	100	t	f
658	28	Abr	2026	100	t	f
660	30	Abr	2026	100	t	f
661	31	Abr	2026	100	t	f
662	32	Abr	2026	100	t	f
663	33	Abr	2026	100	t	f
664	35	Abr	2026	100	t	f
665	36	Abr	2026	100	t	f
666	37	Abr	2026	100	t	f
668	39	Abr	2026	100	t	f
669	40	Abr	2026	100	t	f
670	41	Abr	2026	100	t	f
671	42	Abr	2026	100	t	f
672	43	Abr	2026	100	t	f
673	44	Abr	2026	100	t	f
674	45	Abr	2026	100	t	f
675	46	Abr	2026	100	t	f
677	48	Abr	2026	100	t	f
678	49	Abr	2026	50	t	f
679	50	Abr	2026	100	t	f
680	51	Abr	2026	100	t	f
681	52	Abr	2026	100	t	f
682	53	Abr	2026	0	t	f
683	54	Abr	2026	100	t	f
684	55	Abr	2026	100	t	f
685	57	Abr	2026	100	t	f
686	58	Abr	2026	100	t	f
687	59	Abr	2026	100	t	f
688	60	Abr	2026	100	t	f
689	61	Abr	2026	100	t	f
690	64	Abr	2026	100	t	f
691	65	Abr	2026	100	t	f
692	66	Abr	2026	100	t	f
693	67	Abr	2026	100	t	f
694	68	Abr	2026	100	t	f
696	70	Abr	2026	100	t	f
697	71	Abr	2026	100	t	f
698	72	Abr	2026	100	t	f
699	73	Abr	2026	100	t	f
700	74	Abr	2026	100	t	f
702	76	Abr	2026	100	t	f
703	77	Abr	2026	100	t	f
704	78	Abr	2026	100	t	f
705	79	Abr	2026	100	t	f
707	81	Abr	2026	100	t	f
708	82	Abr	2026	100	t	f
709	83	Abr	2026	100	t	f
710	84	Abr	2026	100	t	f
711	85	Abr	2026	100	t	f
712	86	Abr	2026	100	t	f
713	87	Abr	2026	100	t	f
714	88	Abr	2026	100	t	f
716	90	Abr	2026	100	t	f
717	91	Abr	2026	100	t	f
718	93	Abr	2026	100	t	f
719	94	Abr	2026	100	t	f
720	95	Abr	2026	100	t	f
721	96	Abr	2026	100	t	f
722	97	Abr	2026	100	t	f
723	98	Abr	2026	100	t	f
724	99	Abr	2026	100	t	f
725	100	Abr	2026	0	t	f
726	101	Abr	2026	100	t	f
727	102	Abr	2026	100	t	f
728	103	Abr	2026	100	t	f
729	104	Abr	2026	100	t	f
730	105	Abr	2026	100	t	f
731	106	Abr	2026	50	t	f
732	107	Abr	2026	100	t	f
734	109	Abr	2026	100	t	f
735	110	Abr	2026	100	t	f
736	111	Abr	2026	100	t	f
737	112	Abr	2026	100	t	f
738	113	Abr	2026	0	t	f
739	114	Abr	2026	100	t	f
740	115	Abr	2026	100	t	f
741	116	Abr	2026	100	t	f
742	117	Abr	2026	100	t	f
743	118	Abr	2026	100	t	f
744	119	Abr	2026	100	t	f
745	120	Abr	2026	100	t	f
746	121	Abr	2026	100	t	f
747	122	Abr	2026	100	t	f
748	123	Abr	2026	100	t	f
749	124	Abr	2026	100	t	f
750	125	Abr	2026	100	t	f
751	126	Abr	2026	100	t	f
753	128	Abr	2026	100	t	f
754	129	Abr	2026	100	t	f
756	131	Abr	2026	100	t	f
757	132	Abr	2026	100	t	f
758	133	Abr	2026	100	t	f
759	134	Abr	2026	100	t	f
760	135	Abr	2026	0	t	f
761	136	Abr	2026	100	t	f
762	137	Abr	2026	100	t	f
763	138	Abr	2026	100	t	f
764	139	Abr	2026	100	t	f
765	141	Abr	2026	100	t	f
766	142	Abr	2026	100	t	f
767	143	Abr	2026	100	t	f
768	144	Abr	2026	100	t	f
770	146	Abr	2026	100	t	f
771	147	Abr	2026	100	t	f
772	148	Abr	2026	100	t	f
773	149	Abr	2026	100	t	f
774	150	Abr	2026	100	t	f
775	151	Abr	2026	100	t	f
777	153	Abr	2026	100	t	f
778	154	Abr	2026	100	t	f
779	155	Abr	2026	100	t	f
782	158	Abr	2026	100	t	f
783	159	Abr	2026	100	t	f
784	160	Abr	2026	100	t	f
786	162	Abr	2026	100	t	f
787	163	Abr	2026	100	t	f
788	164	Abr	2026	100	t	f
789	165	Abr	2026	100	t	f
790	166	Abr	2026	100	t	f
791	1	Mai	2026	100	t	f
792	2	Mai	2026	100	t	f
793	3	Mai	2026	100	t	f
794	5	Mai	2026	100	t	f
795	6	Mai	2026	100	t	f
796	7	Mai	2026	100	t	f
798	9	Mai	2026	100	t	f
799	10	Mai	2026	100	t	f
800	11	Mai	2026	100	t	f
801	12	Mai	2026	100	t	f
802	13	Mai	2026	100	t	f
804	15	Mai	2026	100	t	f
805	16	Mai	2026	100	t	f
806	17	Mai	2026	100	t	f
807	19	Mai	2026	100	t	f
808	20	Mai	2026	100	t	f
809	21	Mai	2026	100	t	f
810	22	Mai	2026	100	t	f
811	23	Mai	2026	0	t	f
812	24	Mai	2026	100	t	f
813	25	Mai	2026	100	t	f
814	26	Mai	2026	100	t	f
816	28	Mai	2026	100	t	f
818	30	Mai	2026	100	t	f
819	31	Mai	2026	100	t	f
820	32	Mai	2026	100	t	f
821	33	Mai	2026	100	t	f
822	35	Mai	2026	100	t	f
823	36	Mai	2026	100	t	f
824	37	Mai	2026	100	t	f
826	39	Mai	2026	100	t	f
827	40	Mai	2026	100	t	f
828	41	Mai	2026	100	t	f
829	42	Mai	2026	100	t	f
830	43	Mai	2026	100	t	f
831	44	Mai	2026	100	t	f
832	45	Mai	2026	100	t	f
833	46	Mai	2026	100	t	f
835	48	Mai	2026	100	t	f
836	49	Mai	2026	0	t	f
837	50	Mai	2026	100	t	f
838	51	Mai	2026	100	t	f
839	52	Mai	2026	100	t	f
840	53	Mai	2026	0	t	f
841	54	Mai	2026	100	t	f
842	55	Mai	2026	100	t	f
843	57	Mai	2026	100	t	f
844	58	Mai	2026	100	t	f
845	59	Mai	2026	100	t	f
846	60	Mai	2026	100	t	f
847	61	Mai	2026	100	t	f
848	64	Mai	2026	100	t	f
849	65	Mai	2026	100	t	f
850	66	Mai	2026	100	t	f
851	67	Mai	2026	100	t	f
852	68	Mai	2026	100	t	f
854	70	Mai	2026	100	t	f
855	71	Mai	2026	100	t	f
856	72	Mai	2026	100	t	f
857	73	Mai	2026	100	t	f
858	74	Mai	2026	100	t	f
860	76	Mai	2026	100	t	f
861	77	Mai	2026	100	t	f
862	78	Mai	2026	100	t	f
863	79	Mai	2026	100	t	f
865	81	Mai	2026	100	t	f
866	82	Mai	2026	100	t	f
867	83	Mai	2026	100	t	f
868	84	Mai	2026	100	t	f
869	85	Mai	2026	100	t	f
870	86	Mai	2026	100	t	f
871	87	Mai	2026	100	t	f
872	88	Mai	2026	100	t	f
874	90	Mai	2026	100	t	f
875	91	Mai	2026	100	t	f
876	93	Mai	2026	100	t	f
877	94	Mai	2026	100	t	f
878	95	Mai	2026	100	t	f
879	96	Mai	2026	100	t	f
880	97	Mai	2026	100	t	f
881	98	Mai	2026	100	t	f
882	99	Mai	2026	100	t	f
883	100	Mai	2026	0	t	f
884	101	Mai	2026	100	t	f
885	102	Mai	2026	100	t	f
886	103	Mai	2026	100	t	f
887	104	Mai	2026	100	t	f
888	105	Mai	2026	100	t	f
889	106	Mai	2026	0	t	f
890	107	Mai	2026	100	t	f
892	109	Mai	2026	100	t	f
893	110	Mai	2026	100	t	f
894	111	Mai	2026	100	t	f
895	112	Mai	2026	100	t	f
896	113	Mai	2026	0	t	f
897	114	Mai	2026	100	t	f
898	115	Mai	2026	100	t	f
899	116	Mai	2026	100	t	f
900	117	Mai	2026	100	t	f
901	118	Mai	2026	100	t	f
902	119	Mai	2026	100	t	f
903	120	Mai	2026	100	t	f
904	121	Mai	2026	100	t	f
905	122	Mai	2026	100	t	f
906	123	Mai	2026	100	t	f
907	124	Mai	2026	100	t	f
908	125	Mai	2026	100	t	f
909	126	Mai	2026	100	t	f
911	128	Mai	2026	100	t	f
912	129	Mai	2026	100	t	f
914	131	Mai	2026	100	t	f
915	132	Mai	2026	100	t	f
916	133	Mai	2026	100	t	f
917	134	Mai	2026	100	t	f
918	135	Mai	2026	0	t	f
919	136	Mai	2026	100	t	f
920	137	Mai	2026	100	t	f
921	138	Mai	2026	100	t	f
922	139	Mai	2026	100	t	f
923	141	Mai	2026	100	t	f
924	142	Mai	2026	100	t	f
925	143	Mai	2026	100	t	f
926	144	Mai	2026	100	t	f
928	146	Mai	2026	100	t	f
929	147	Mai	2026	100	t	f
930	148	Mai	2026	100	t	f
931	149	Mai	2026	100	t	f
932	150	Mai	2026	100	t	f
933	151	Mai	2026	100	t	f
935	153	Mai	2026	100	t	f
936	154	Mai	2026	100	t	f
937	155	Mai	2026	100	t	f
940	158	Mai	2026	100	t	f
941	159	Mai	2026	100	t	f
942	160	Mai	2026	100	t	f
944	162	Mai	2026	100	t	f
945	163	Mai	2026	100	t	f
946	164	Mai	2026	100	t	f
947	165	Mai	2026	100	t	f
948	166	Mai	2026	100	t	f
949	18	Dez	2025	100	t	f
950	34	Dez	2025	100	t	f
951	167	Dez	2025	100	t	f
952	168	Dez	2025	100	t	f
953	169	Dez	2025	100	t	f
954	18	Jan	2026	100	t	f
955	34	Jan	2026	100	t	f
956	167	Jan	2026	100	t	f
957	169	Jan	2026	100	t	f
958	18	Fev	2026	100	t	f
959	34	Fev	2026	100	t	f
960	167	Fev	2026	100	t	f
961	169	Fev	2026	100	t	f
962	18	Mar	2026	100	t	f
963	34	Mar	2026	100	t	f
964	167	Mar	2026	100	t	f
965	169	Mar	2026	100	t	f
966	18	Abr	2026	100	t	f
967	34	Abr	2026	100	t	f
968	167	Abr	2026	100	t	f
969	169	Abr	2026	100	t	f
970	18	Mai	2026	100	t	f
971	34	Mai	2026	100	t	f
972	167	Mai	2026	100	t	f
973	169	Mai	2026	100	t	f
974	170	Dez	2025	100	t	f
975	170	Jan	2026	100	t	f
976	170	Fev	2026	100	t	f
977	170	Mar	2026	40	t	f
978	170	Abr	2026	100	t	f
979	170	Mai	2026	100	t	f
980	171	Mar	2026	100	t	f
981	171	Abr	2026	100	t	f
982	171	Mai	2026	0	t	f
983	171	Jun	2026	60	t	f
984	171	Jul	2026	0	t	f
985	171	Ago	2026	0	t	f
986	172	Mar	2026	100	t	f
987	172	Abr	2026	100	t	f
988	172	Mai	2026	100	t	f
989	172	Jun	2026	100	t	f
990	172	Jul	2026	100	t	f
991	172	Ago	2026	100	t	f
992	173	Mar	2026	100	t	f
993	173	Abr	2026	100	t	f
994	173	Mai	2026	100	t	f
995	173	Jun	2026	100	t	f
996	173	Jul	2026	100	t	f
997	173	Ago	2026	100	t	f
998	174	Mar	2026	100	t	f
999	174	Abr	2026	100	t	f
1000	174	Mai	2026	100	t	f
1001	174	Jun	2026	100	t	f
1002	174	Jul	2026	100	t	f
1003	174	Ago	2026	100	t	f
1004	175	Mar	2026	100	t	f
1005	175	Abr	2026	100	t	f
1006	175	Mai	2026	10	t	f
1007	175	Jun	2026	40	t	f
1008	175	Jul	2026	20	t	f
1009	175	Ago	2026	40	t	f
1010	176	Mar	2026	100	t	f
1011	176	Abr	2026	100	t	f
1012	176	Mai	2026	100	t	f
1013	176	Jun	2026	100	t	f
1014	176	Jul	2026	100	t	f
1015	176	Ago	2026	100	t	f
1016	170	Jun	2026	60	t	f
1017	170	Jul	2026	25	t	f
1018	170	Ago	2026	50	t	f
1019	177	Mar	2026	100	t	f
1020	177	Abr	2026	100	t	f
1021	177	Mai	2026	100	t	f
1022	177	Jun	2026	100	t	f
1023	177	Jul	2026	100	t	f
1024	177	Ago	2026	100	t	f
1025	178	Mar	2026	100	t	f
1026	178	Abr	2026	100	t	f
1027	178	Mai	2026	100	t	f
1028	178	Jun	2026	100	t	f
1029	178	Jul	2026	100	t	f
1030	178	Ago	2026	100	t	f
1031	179	Mar	2026	90	t	f
1032	179	Abr	2026	0	t	f
1033	179	Mai	2026	15	t	f
1034	179	Jun	2026	60	t	f
1035	179	Jul	2026	0	t	f
1036	179	Ago	2026	0	t	f
1037	180	Mar	2026	90	t	f
1038	180	Abr	2026	60	t	f
1039	180	Mai	2026	75	t	f
1040	180	Jun	2026	100	t	f
1041	180	Jul	2026	0	t	f
1042	180	Ago	2026	75	t	f
1043	181	Mar	2026	90	t	f
1044	181	Abr	2026	50	t	f
1045	181	Mai	2026	85	t	f
1046	181	Jun	2026	100	t	f
1047	181	Jul	2026	28	t	f
1048	181	Ago	2026	30	t	f
1049	182	Mar	2026	90	t	f
1050	182	Abr	2026	25	t	f
1051	182	Mai	2026	55	t	f
1052	182	Jun	2026	60	t	f
1053	182	Jul	2026	100	t	f
1054	182	Ago	2026	100	t	f
1055	183	Mar	2026	30	t	f
1056	183	Abr	2026	25	t	f
1057	183	Mai	2026	5	t	f
1058	183	Jun	2026	10	t	f
1059	183	Jul	2026	0	t	f
1060	183	Ago	2026	0	t	f
1061	184	Mar	2026	90	t	f
1062	184	Abr	2026	15	t	f
1063	184	Mai	2026	0	t	f
1064	184	Jun	2026	0	t	f
1065	184	Jul	2026	0	t	f
1066	184	Ago	2026	0	t	f
1067	185	Mar	2026	100	t	f
1068	185	Abr	2026	100	t	f
1069	185	Mai	2026	0	t	f
1070	185	Jun	2026	0	t	f
1071	185	Jul	2026	0	t	f
1072	185	Ago	2026	0	t	f
1073	186	Mar	2026	60	t	f
1074	186	Abr	2026	0	t	f
1075	186	Mai	2026	0	t	f
1076	186	Jun	2026	40	t	f
1077	186	Jul	2026	10	t	f
1078	186	Ago	2026	20	t	f
1079	187	Mar	2026	50	t	f
1080	187	Abr	2026	50	t	f
1081	187	Mai	2026	75	t	f
1082	187	Jun	2026	100	t	f
1083	187	Jul	2026	0	t	f
1084	187	Ago	2026	25	t	f
1085	135	Jun	2026	0	t	f
1086	135	Jul	2026	0	t	f
1087	135	Ago	2026	0	t	f
1088	188	Mar	2026	100	t	f
1089	188	Abr	2026	100	t	f
1090	188	Mai	2026	0	t	f
1091	188	Jun	2026	0	t	f
1092	188	Jul	2026	0	t	f
1093	188	Ago	2026	0	t	f
1094	189	Mar	2026	100	t	f
1095	189	Abr	2026	0	t	f
1096	189	Mai	2026	0	t	f
1097	189	Jun	2026	0	t	f
1098	189	Jul	2026	0	t	f
1099	189	Ago	2026	0	t	f
1100	190	Mar	2026	100	t	f
1101	190	Abr	2026	100	t	f
1102	190	Mai	2026	0	t	f
1103	190	Jun	2026	0	t	f
1104	190	Jul	2026	0	t	f
1105	190	Ago	2026	0	t	f
1106	191	Mar	2026	50	t	f
1107	191	Abr	2026	50	t	f
1108	191	Mai	2026	0	t	f
1109	191	Jun	2026	0	t	f
1110	191	Jul	2026	0	t	f
1111	191	Ago	2026	0	t	f
1112	192	Mar	2026	50	t	f
1113	192	Abr	2026	50	t	f
1114	192	Mai	2026	25	t	f
1115	192	Jun	2026	50	t	f
1116	192	Jul	2026	0	t	f
1117	192	Ago	2026	0	t	f
1118	193	Mar	2026	50	t	f
1119	193	Abr	2026	50	t	f
1120	193	Mai	2026	0	t	f
1121	193	Jun	2026	0	t	f
1122	193	Jul	2026	0	t	f
1123	193	Ago	2026	0	t	f
1124	194	Mar	2026	50	t	f
1125	194	Abr	2026	50	t	f
1126	194	Mai	2026	60	t	f
1127	194	Jun	2026	75	t	f
1128	194	Jul	2026	45	t	f
1129	194	Ago	2026	45	t	f
1130	195	Mar	2026	50	t	f
1131	195	Abr	2026	63	t	f
1132	195	Mai	2026	0	t	f
1133	195	Jun	2026	0	t	f
1134	195	Jul	2026	0	t	f
1135	195	Ago	2026	0	t	f
1136	196	Mar	2026	40	t	f
1137	196	Abr	2026	16	t	f
1138	196	Mai	2026	0	t	f
1139	196	Jun	2026	0	t	f
1140	196	Jul	2026	0	t	f
1141	196	Ago	2026	0	t	f
1142	197	Mar	2026	50	t	f
1143	197	Abr	2026	20	t	f
1144	197	Mai	2026	20	t	f
1145	197	Jun	2026	20	t	f
1146	197	Jul	2026	10	t	f
1147	197	Ago	2026	0	t	f
1148	198	Mar	2026	50	t	f
1149	198	Abr	2026	80	t	f
1150	198	Mai	2026	80	t	f
1151	198	Jun	2026	80	t	f
1152	198	Jul	2026	90	t	f
1153	198	Ago	2026	0	t	f
1154	199	Mar	2026	0	t	f
1155	199	Abr	2026	50	t	f
1156	199	Mai	2026	100	t	f
1157	199	Jun	2026	100	t	f
1158	199	Jul	2026	100	t	f
1159	199	Ago	2026	100	t	f
1160	200	Mar	2026	0	t	f
1161	200	Abr	2026	50	t	f
1162	200	Mai	2026	0	t	f
1163	200	Jun	2026	0	t	f
1164	200	Jul	2026	0	t	f
1165	200	Ago	2026	0	t	f
1166	201	Mar	2026	90	t	f
1167	201	Abr	2026	100	t	f
1168	201	Mai	2026	100	t	f
1169	201	Jun	2026	100	t	f
1170	201	Jul	2026	43	t	f
1171	201	Ago	2026	100	t	f
1172	202	Mar	2026	10	t	f
1173	202	Abr	2026	0	t	f
1174	202	Mai	2026	0	t	f
1175	202	Jun	2026	0	t	f
1176	202	Jul	2026	0	t	f
1177	202	Ago	2026	0	t	f
1178	203	Mar	2026	90	t	f
1179	203	Abr	2026	25	t	f
1180	203	Mai	2026	55	t	f
1181	203	Jun	2026	60	t	f
1182	203	Jul	2026	40	t	f
1183	203	Ago	2026	0	t	f
1184	204	Mar	2026	100	t	f
1185	204	Abr	2026	30	t	f
1186	204	Mai	2026	0	t	f
1187	204	Jun	2026	40	t	f
1188	204	Jul	2026	0	t	f
1189	204	Ago	2026	0	t	f
1190	205	Mar	2026	50	t	f
1191	205	Abr	2026	50	t	f
1192	205	Mai	2026	50	t	f
1193	205	Jun	2026	0	t	f
1194	205	Jul	2026	0	t	f
1195	205	Ago	2026	0	t	f
1196	206	Mar	2026	50	t	f
1197	206	Abr	2026	50	t	f
1198	206	Mai	2026	50	t	f
1199	206	Jun	2026	0	t	f
1200	206	Jul	2026	0	t	f
1201	206	Ago	2026	0	t	f
1202	207	Mar	2026	50	t	f
1203	207	Abr	2026	50	t	f
1204	207	Mai	2026	0	t	f
1205	207	Jun	2026	0	t	f
1206	207	Jul	2026	0	t	f
1207	207	Ago	2026	0	t	f
1208	23	Jun	2026	0	t	f
1209	23	Jul	2026	0	t	f
1210	23	Ago	2026	0	t	f
1211	208	Mar	2026	50	t	f
1212	208	Abr	2026	50	t	f
1213	208	Mai	2026	40	t	f
1214	208	Jun	2026	75	t	f
1215	208	Jul	2026	20	t	f
1216	208	Ago	2026	0	t	f
1217	209	Mar	2026	90	t	f
1218	209	Abr	2026	15	t	f
1219	209	Mai	2026	85	t	f
1220	209	Jun	2026	50	t	f
1221	209	Jul	2026	87	t	f
1222	209	Ago	2026	100	t	f
1223	210	Mar	2026	100	t	f
1224	210	Abr	2026	100	t	f
1225	210	Mai	2026	100	t	f
1226	210	Jun	2026	100	t	f
1227	210	Jul	2026	0	t	f
1228	210	Ago	2026	50	t	f
1229	211	Mar	2026	100	t	f
1230	211	Abr	2026	100	t	f
1231	211	Mai	2026	100	t	f
1232	211	Jun	2026	100	t	f
1233	211	Jul	2026	100	t	f
1234	211	Ago	2026	0	t	f
1235	212	Mar	2026	100	t	f
1236	212	Abr	2026	100	t	f
1237	212	Mai	2026	0	t	f
1238	212	Jun	2026	0	t	f
1239	212	Jul	2026	0	t	f
1240	212	Ago	2026	0	t	f
1241	213	Mar	2026	0	t	f
1242	213	Abr	2026	0	t	f
1243	213	Mai	2026	0	t	f
1244	213	Jun	2026	0	t	f
1245	213	Jul	2026	0	t	f
1246	213	Ago	2026	0	t	f
1247	214	Mar	2026	50	t	f
1248	214	Abr	2026	50	t	f
1249	214	Mai	2026	50	t	f
1250	214	Jun	2026	50	t	f
1251	214	Jul	2026	50	t	f
1252	214	Ago	2026	0	t	f
1253	215	Mar	2026	50	t	f
1254	215	Abr	2026	50	t	f
1255	215	Mai	2026	50	t	f
1256	215	Jun	2026	50	t	f
1257	215	Jul	2026	50	t	f
1258	215	Ago	2026	0	t	f
1259	216	Mar	2026	100	t	f
1260	216	Abr	2026	100	t	f
1261	216	Mai	2026	100	t	f
1262	216	Jun	2026	100	t	f
1263	216	Jul	2026	100	t	f
1264	216	Ago	2026	100	t	f
1265	217	Mar	2026	50	t	f
1266	217	Abr	2026	50	t	f
1267	217	Mai	2026	50	t	f
1268	217	Jun	2026	50	t	f
1269	217	Jul	2026	50	t	f
1270	217	Ago	2026	50	t	f
1271	218	Mar	2026	50	t	f
1272	218	Abr	2026	50	t	f
1273	218	Mai	2026	50	t	f
1274	218	Jun	2026	50	t	f
1275	218	Jul	2026	50	t	f
1276	218	Ago	2026	50	t	f
1277	219	Mar	2026	100	t	f
1278	219	Abr	2026	100	t	f
1279	219	Mai	2026	100	t	f
1280	219	Jun	2026	100	t	f
1281	219	Jul	2026	100	t	f
1282	219	Ago	2026	100	t	f
1283	220	Mar	2026	100	t	f
1284	220	Abr	2026	100	t	f
1285	220	Mai	2026	100	t	f
1286	220	Jun	2026	100	t	f
1287	220	Jul	2026	0	t	f
1288	220	Ago	2026	0	t	f
1289	221	Mar	2026	100	t	f
1290	221	Abr	2026	100	t	f
1291	221	Mai	2026	100	t	f
1292	221	Jun	2026	100	t	f
1293	221	Jul	2026	100	t	f
1294	221	Ago	2026	100	t	f
1295	222	Mar	2026	100	t	f
1296	222	Abr	2026	100	t	f
1297	222	Mai	2026	100	t	f
1298	222	Jun	2026	100	t	f
1299	222	Jul	2026	100	t	f
1300	222	Ago	2026	100	t	f
1301	223	Mar	2026	100	t	f
1302	223	Abr	2026	100	t	f
1303	223	Mai	2026	100	t	f
1304	223	Jun	2026	100	t	f
1305	223	Jul	2026	100	t	f
1306	223	Ago	2026	100	t	f
1307	224	Mar	2026	100	t	f
1308	224	Abr	2026	100	t	f
1309	224	Mai	2026	100	t	f
1310	224	Jun	2026	100	t	f
1311	224	Jul	2026	100	t	f
1312	224	Ago	2026	100	t	f
1313	225	Mar	2026	100	t	f
1314	225	Abr	2026	100	t	f
1315	225	Mai	2026	100	t	f
1316	225	Jun	2026	100	t	f
1317	225	Jul	2026	100	t	f
1318	225	Ago	2026	100	t	f
1319	226	Mar	2026	100	t	f
1320	226	Abr	2026	100	t	f
1321	226	Mai	2026	100	t	f
1322	226	Jun	2026	100	t	f
1323	226	Jul	2026	100	t	f
1324	226	Ago	2026	100	t	f
1325	227	Mar	2026	100	t	f
1326	227	Abr	2026	100	t	f
1327	227	Mai	2026	100	t	f
1328	227	Jun	2026	100	t	f
1329	227	Jul	2026	100	t	f
1330	227	Ago	2026	0	t	f
1331	228	Mar	2026	100	t	f
1332	228	Abr	2026	100	t	f
1333	228	Mai	2026	100	t	f
1334	228	Jun	2026	100	t	f
1335	228	Jul	2026	100	t	f
1336	228	Ago	2026	100	t	f
1337	229	Mar	2026	100	t	f
1338	229	Abr	2026	100	t	f
1339	229	Mai	2026	100	t	f
1340	229	Jun	2026	100	t	f
1341	229	Jul	2026	100	t	f
1342	229	Ago	2026	100	t	f
1343	230	Mar	2026	100	t	f
1344	230	Abr	2026	100	t	f
1345	230	Mai	2026	100	t	f
1346	230	Jun	2026	100	t	f
1347	230	Jul	2026	0	t	f
1348	230	Ago	2026	0	t	f
1349	231	Mar	2026	100	t	f
1350	231	Abr	2026	100	t	f
1351	231	Mai	2026	100	t	f
1352	231	Jun	2026	100	t	f
1353	231	Jul	2026	100	t	f
1354	231	Ago	2026	100	t	f
1355	232	Mar	2026	100	t	f
1356	232	Abr	2026	100	t	f
1357	232	Mai	2026	100	t	f
1358	232	Jun	2026	100	t	f
1359	232	Jul	2026	100	t	f
1360	232	Ago	2026	100	t	f
1361	233	Mar	2026	100	t	f
1362	233	Abr	2026	100	t	f
1363	233	Mai	2026	100	t	f
1364	233	Jun	2026	100	t	f
1365	233	Jul	2026	100	t	f
1366	233	Ago	2026	100	t	f
1367	234	Mar	2026	100	t	f
1368	234	Abr	2026	100	t	f
1369	234	Mai	2026	100	t	f
1370	234	Jun	2026	100	t	f
1371	234	Jul	2026	100	t	f
1372	234	Ago	2026	100	t	f
1373	235	Mar	2026	100	t	f
1374	235	Abr	2026	100	t	f
1375	235	Mai	2026	100	t	f
1376	235	Jun	2026	100	t	f
1377	235	Jul	2026	100	t	f
1378	235	Ago	2026	100	t	f
1379	236	Mar	2026	100	t	f
1380	236	Abr	2026	100	t	f
1381	236	Mai	2026	100	t	f
1382	236	Jun	2026	100	t	f
1383	236	Jul	2026	100	t	f
1384	236	Ago	2026	100	t	f
1385	106	Jun	2026	0	t	f
1386	106	Jul	2026	0	t	f
1387	106	Ago	2026	0	t	f
1388	49	Jun	2026	0	t	f
1389	49	Jul	2026	0	t	f
1390	49	Ago	2026	0	t	f
1391	237	Mar	2026	100	t	f
1392	237	Abr	2026	100	t	f
1393	237	Mai	2026	100	t	f
1394	237	Jun	2026	100	t	f
1395	237	Jul	2026	100	t	f
1396	237	Ago	2026	100	t	f
1397	238	Mar	2026	100	t	f
1398	238	Abr	2026	100	t	f
1399	238	Mai	2026	100	t	f
1400	238	Jun	2026	100	t	f
1401	238	Jul	2026	100	t	f
1402	238	Ago	2026	100	t	f
1403	239	Mar	2026	100	t	f
1404	239	Abr	2026	100	t	f
1405	239	Mai	2026	100	t	f
1406	239	Jun	2026	100	t	f
1407	239	Jul	2026	100	t	f
1408	239	Ago	2026	100	t	f
1409	240	Mar	2026	100	t	f
1410	240	Abr	2026	100	t	f
1411	240	Mai	2026	100	t	f
1412	240	Jun	2026	100	t	f
1413	240	Jul	2026	100	t	f
1414	240	Ago	2026	100	t	f
1415	159	Jun	2026	100	t	f
1416	159	Jul	2026	100	t	f
1417	159	Ago	2026	100	t	f
1418	54	Jun	2026	100	t	f
1419	54	Jul	2026	100	t	f
1420	54	Ago	2026	100	t	f
1421	57	Jun	2026	100	t	f
1422	57	Jul	2026	100	t	f
1423	57	Ago	2026	100	t	f
1424	120	Jun	2026	100	t	f
1425	120	Jul	2026	100	t	f
1426	120	Ago	2026	100	t	f
1427	96	Jun	2026	100	t	f
1428	96	Jul	2026	100	t	f
1429	96	Ago	2026	100	t	f
1430	160	Jun	2026	100	t	f
1431	160	Jul	2026	100	t	f
1432	160	Ago	2026	100	t	f
1433	6	Jun	2026	100	t	f
1434	6	Jul	2026	100	t	f
1435	6	Ago	2026	100	t	f
1436	19	Jun	2026	100	t	f
1437	19	Jul	2026	100	t	f
1438	19	Ago	2026	100	t	f
1439	241	Mar	2026	100	t	f
1440	241	Abr	2026	100	t	f
1441	241	Mai	2026	100	t	f
1442	241	Jun	2026	100	t	f
1443	241	Jul	2026	100	t	f
1444	241	Ago	2026	100	t	f
1445	242	Mar	2026	100	t	f
1446	242	Abr	2026	100	t	f
1447	242	Mai	2026	100	t	f
1448	242	Jun	2026	100	t	f
1449	242	Jul	2026	100	t	f
1450	242	Ago	2026	100	t	f
1451	243	Mar	2026	100	t	f
1452	243	Abr	2026	100	t	f
1453	243	Mai	2026	100	t	f
1454	243	Jun	2026	100	t	f
1455	243	Jul	2026	100	t	f
1456	243	Ago	2026	100	t	f
1457	244	Mar	2026	100	t	f
1458	244	Abr	2026	100	t	f
1459	244	Mai	2026	100	t	f
1460	244	Jun	2026	100	t	f
1461	244	Jul	2026	100	t	f
1462	244	Ago	2026	100	t	f
1463	245	Mar	2026	100	t	f
1464	245	Abr	2026	100	t	f
1465	245	Mai	2026	100	t	f
1466	245	Jun	2026	100	t	f
1467	245	Jul	2026	100	t	f
1468	245	Ago	2026	100	t	f
1469	246	Mar	2026	100	t	f
1470	246	Abr	2026	100	t	f
1471	246	Mai	2026	100	t	f
1472	246	Jun	2026	100	t	f
1473	246	Jul	2026	100	t	f
1474	246	Ago	2026	100	t	f
1475	247	Mar	2026	50	t	f
1476	247	Abr	2026	50	t	f
1477	247	Mai	2026	50	t	f
1478	247	Jun	2026	50	t	f
1479	247	Jul	2026	50	t	f
1480	247	Ago	2026	50	t	f
1481	248	Mar	2026	100	t	f
1482	248	Abr	2026	100	t	f
1483	248	Mai	2026	100	t	f
1484	248	Jun	2026	0	t	f
1485	248	Jul	2026	0	t	f
1486	248	Ago	2026	0	t	f
1487	249	Mar	2026	100	t	f
1488	249	Abr	2026	100	t	f
1489	249	Mai	2026	100	t	f
1490	249	Jun	2026	100	t	f
1491	249	Jul	2026	100	t	f
1492	249	Ago	2026	100	t	f
1493	250	Mar	2026	100	t	f
1494	250	Abr	2026	100	t	f
1495	250	Mai	2026	0	t	f
1496	250	Jun	2026	0	t	f
1497	250	Jul	2026	0	t	f
1498	250	Ago	2026	0	t	f
1499	251	Mar	2026	100	t	f
1500	251	Abr	2026	100	t	f
1501	251	Mai	2026	100	t	f
1502	251	Jun	2026	100	t	f
1503	251	Jul	2026	100	t	f
1504	251	Ago	2026	100	t	f
1505	252	Mar	2026	100	t	f
1506	252	Abr	2026	100	t	f
1507	252	Mai	2026	100	t	f
1508	252	Jun	2026	100	t	f
1509	252	Jul	2026	100	t	f
1510	252	Ago	2026	100	t	f
1511	253	Mar	2026	100	t	f
1512	253	Abr	2026	0	t	f
1513	253	Mai	2026	0	t	f
1514	253	Jun	2026	0	t	f
1515	253	Jul	2026	0	t	f
1516	253	Ago	2026	0	t	f
1517	254	Mar	2026	100	t	f
1518	254	Abr	2026	100	t	f
1519	254	Mai	2026	100	t	f
1520	254	Jun	2026	100	t	f
1521	254	Jul	2026	100	t	f
1522	254	Ago	2026	100	t	f
1523	255	Mar	2026	100	t	f
1524	255	Abr	2026	100	t	f
1525	255	Mai	2026	100	t	f
1526	255	Jun	2026	100	t	f
1527	255	Jul	2026	100	t	f
1528	255	Ago	2026	100	t	f
1529	256	Mar	2026	100	t	f
1530	256	Abr	2026	100	t	f
1531	256	Mai	2026	100	t	f
1532	256	Jun	2026	100	t	f
1533	256	Jul	2026	100	t	f
1534	256	Ago	2026	100	t	f
1535	257	Mar	2026	100	t	f
1536	257	Abr	2026	100	t	f
1537	257	Mai	2026	100	t	f
1538	257	Jun	2026	100	t	f
1539	257	Jul	2026	100	t	f
1540	257	Ago	2026	100	t	f
1541	258	Mar	2026	100	t	f
1542	258	Abr	2026	100	t	f
1543	258	Mai	2026	100	t	f
1544	258	Jun	2026	100	t	f
1545	258	Jul	2026	100	t	f
1546	258	Ago	2026	100	t	f
1547	259	Mar	2026	50	t	f
1548	259	Abr	2026	50	t	f
1549	259	Mai	2026	50	t	f
1550	259	Jun	2026	0	t	f
1551	259	Jul	2026	0	t	f
1552	259	Ago	2026	0	t	f
1553	260	Mar	2026	50	t	f
1554	260	Abr	2026	50	t	f
1555	260	Mai	2026	50	t	f
1556	260	Jun	2026	0	t	f
1557	260	Jul	2026	0	t	f
1558	260	Ago	2026	0	t	f
1559	261	Mar	2026	100	t	f
1560	261	Abr	2026	0	t	f
1561	261	Mai	2026	0	t	f
1562	261	Jun	2026	0	t	f
1563	261	Jul	2026	0	t	f
1564	261	Ago	2026	0	t	f
1565	262	Mar	2026	100	t	f
1566	262	Abr	2026	100	t	f
1567	262	Mai	2026	100	t	f
1568	262	Jun	2026	0	t	f
1569	262	Jul	2026	0	t	f
1570	262	Ago	2026	0	t	f
1571	263	Mar	2026	100	t	f
1572	263	Abr	2026	100	t	f
1573	263	Mai	2026	100	t	f
1574	263	Jun	2026	0	t	f
1575	263	Jul	2026	0	t	f
1576	263	Ago	2026	0	t	f
1577	264	Mar	2026	100	t	f
1578	264	Abr	2026	100	t	f
1579	264	Mai	2026	100	t	f
1580	264	Jun	2026	0	t	f
1581	264	Jul	2026	0	t	f
1582	264	Ago	2026	0	t	f
1583	265	Mar	2026	100	t	f
1584	265	Abr	2026	100	t	f
1585	265	Mai	2026	100	t	f
1586	265	Jun	2026	0	t	f
1587	265	Jul	2026	0	t	f
1588	265	Ago	2026	0	t	f
1589	266	Mar	2026	100	t	f
1590	266	Abr	2026	100	t	f
1591	266	Mai	2026	100	t	f
1592	266	Jun	2026	0	t	f
1593	266	Jul	2026	0	t	f
1594	266	Ago	2026	0	t	f
1595	267	Mar	2026	100	t	f
1596	267	Abr	2026	100	t	f
1597	267	Mai	2026	100	t	f
1598	267	Jun	2026	0	t	f
1599	267	Jul	2026	0	t	f
1600	267	Ago	2026	0	t	f
1601	268	Mar	2026	100	t	f
1602	268	Abr	2026	100	t	f
1603	268	Mai	2026	100	t	f
1604	268	Jun	2026	0	t	f
1605	268	Jul	2026	0	t	f
1606	268	Ago	2026	0	t	f
1607	269	Mar	2026	100	t	f
1608	269	Abr	2026	100	t	f
1609	269	Mai	2026	100	t	f
1610	269	Jun	2026	100	t	f
1611	269	Jul	2026	20	t	f
1612	269	Ago	2026	0	t	f
1613	270	Mar	2026	100	t	f
1614	270	Abr	2026	100	t	f
1615	270	Mai	2026	100	t	f
1616	270	Jun	2026	0	t	f
1617	270	Jul	2026	0	t	f
1618	270	Ago	2026	0	t	f
1619	271	Mar	2026	100	t	f
1620	271	Abr	2026	100	t	f
1621	271	Mai	2026	100	t	f
1622	271	Jun	2026	0	t	f
1623	271	Jul	2026	0	t	f
1624	271	Ago	2026	0	t	f
1625	272	Mar	2026	100	t	f
1626	272	Abr	2026	100	t	f
1627	272	Mai	2026	100	t	f
1628	272	Jun	2026	0	t	f
1629	272	Jul	2026	0	t	f
1630	272	Ago	2026	0	t	f
1631	273	Mar	2026	100	t	f
1632	273	Abr	2026	100	t	f
1633	273	Mai	2026	100	t	f
1634	273	Jun	2026	0	t	f
1635	273	Jul	2026	0	t	f
1636	273	Ago	2026	0	t	f
1637	274	Mar	2026	100	t	f
1638	274	Abr	2026	100	t	f
1639	274	Mai	2026	100	t	f
1640	274	Jun	2026	100	t	f
1641	274	Jul	2026	100	t	f
1642	274	Ago	2026	40	t	f
1643	275	Mar	2026	100	t	f
1644	275	Abr	2026	100	t	f
1645	275	Mai	2026	0	t	f
1646	275	Jun	2026	0	t	f
1647	275	Jul	2026	0	t	f
1648	275	Ago	2026	0	t	f
1649	276	Mar	2026	100	t	f
1650	276	Abr	2026	100	t	f
1651	276	Mai	2026	100	t	f
1652	276	Jun	2026	100	t	f
1653	276	Jul	2026	5	t	f
1654	276	Ago	2026	0	t	f
1655	277	Mar	2026	100	t	f
1656	277	Abr	2026	100	t	f
1657	277	Mai	2026	100	t	f
1658	277	Jun	2026	100	t	f
1659	277	Jul	2026	40	t	f
1660	277	Ago	2026	20	t	f
1661	278	Mar	2026	100	t	f
1662	278	Abr	2026	100	t	f
1663	278	Mai	2026	100	t	f
1664	278	Jun	2026	100	t	f
1665	278	Jul	2026	100	t	f
1666	278	Ago	2026	100	t	f
1667	279	Mar	2026	100	t	f
1668	279	Abr	2026	100	t	f
1669	279	Mai	2026	100	t	f
1670	279	Jun	2026	100	t	f
1671	279	Jul	2026	70	t	f
1672	279	Ago	2026	5	t	f
1673	280	Mar	2026	100	t	f
1674	280	Abr	2026	100	t	f
1675	280	Mai	2026	100	t	f
1676	280	Jun	2026	100	t	f
1677	280	Jul	2026	5	t	f
1678	280	Ago	2026	0	t	f
1679	281	Mar	2026	100	t	f
1680	281	Abr	2026	100	t	f
1681	281	Mai	2026	100	t	f
1682	281	Jun	2026	100	t	f
1683	281	Jul	2026	5	t	f
1684	281	Ago	2026	0	t	f
1685	282	Mar	2026	100	t	f
1686	282	Abr	2026	100	t	f
1687	282	Mai	2026	100	t	f
1688	282	Jun	2026	100	t	f
1689	282	Jul	2026	5	t	f
1690	282	Ago	2026	0	t	f
1691	283	Mar	2026	100	t	f
1692	283	Abr	2026	100	t	f
1693	283	Mai	2026	100	t	f
1694	283	Jun	2026	100	t	f
1695	283	Jul	2026	10	t	f
1696	283	Ago	2026	0	t	f
1697	284	Mar	2026	100	t	f
1698	284	Abr	2026	100	t	f
1699	284	Mai	2026	100	t	f
1700	284	Jun	2026	100	t	f
1701	284	Jul	2026	100	t	f
1702	284	Ago	2026	100	t	f
1703	285	Mar	2026	100	t	f
1704	285	Abr	2026	100	t	f
1705	285	Mai	2026	100	t	f
1706	285	Jun	2026	100	t	f
1707	285	Jul	2026	100	t	f
1708	285	Ago	2026	100	t	f
1709	286	Mar	2026	100	t	f
1710	286	Abr	2026	100	t	f
1711	286	Mai	2026	100	t	f
1712	286	Jun	2026	100	t	f
1713	286	Jul	2026	100	t	f
1714	286	Ago	2026	100	t	f
1715	287	Mar	2026	100	t	f
1716	287	Abr	2026	100	t	f
1717	287	Mai	2026	100	t	f
1718	287	Jun	2026	100	t	f
1719	287	Jul	2026	100	t	f
1720	287	Ago	2026	100	t	f
1721	288	Mar	2026	100	t	f
1722	288	Abr	2026	100	t	f
1723	288	Mai	2026	100	t	f
1724	288	Jun	2026	100	t	f
1725	288	Jul	2026	100	t	f
1726	288	Ago	2026	100	t	f
1727	289	Mar	2026	100	t	f
1728	289	Abr	2026	100	t	f
1729	289	Mai	2026	100	t	f
1730	289	Jun	2026	0	t	f
1731	289	Jul	2026	0	t	f
1732	289	Ago	2026	0	t	f
1733	290	Mar	2026	100	t	f
1734	290	Abr	2026	100	t	f
1735	290	Mai	2026	100	t	f
1736	290	Jun	2026	100	t	f
1737	290	Jul	2026	100	t	f
1738	290	Ago	2026	100	t	f
1739	291	Mar	2026	100	t	f
1740	291	Abr	2026	100	t	f
1741	291	Mai	2026	100	t	f
1742	291	Jun	2026	100	t	f
1743	291	Jul	2026	100	t	f
1744	291	Ago	2026	100	t	f
1745	292	Mar	2026	100	t	f
1746	292	Abr	2026	100	t	f
1747	292	Mai	2026	100	t	f
1748	292	Jun	2026	100	t	f
1749	292	Jul	2026	100	t	f
1750	292	Ago	2026	100	t	f
1751	293	Mar	2026	100	t	f
1752	293	Abr	2026	100	t	f
1753	293	Mai	2026	100	t	f
1754	293	Jun	2026	100	t	f
1755	293	Jul	2026	100	t	f
1756	293	Ago	2026	100	t	f
1757	294	Mar	2026	100	t	f
1758	294	Abr	2026	100	t	f
1759	294	Mai	2026	100	t	f
1760	294	Jun	2026	100	t	f
1761	294	Jul	2026	100	t	f
1762	294	Ago	2026	100	t	f
1763	77	Jun	2026	100	t	f
1764	77	Jul	2026	100	t	f
1765	77	Ago	2026	100	t	f
1766	295	Mar	2026	100	t	f
1767	295	Abr	2026	100	t	f
1768	295	Mai	2026	100	t	f
1769	295	Jun	2026	0	t	f
1770	295	Jul	2026	0	t	f
1771	295	Ago	2026	0	t	f
1772	296	Mar	2026	100	t	f
1773	296	Abr	2026	100	t	f
1774	296	Mai	2026	100	t	f
1775	296	Jun	2026	100	t	f
1776	296	Jul	2026	100	t	f
1777	296	Ago	2026	100	t	f
1778	297	Mar	2026	100	t	f
1779	297	Abr	2026	100	t	f
1780	297	Mai	2026	100	t	f
1781	297	Jun	2026	100	t	f
1782	297	Jul	2026	100	t	f
1783	297	Ago	2026	100	t	f
1784	298	Mar	2026	100	t	f
1785	298	Abr	2026	100	t	f
1786	298	Mai	2026	100	t	f
1787	298	Jun	2026	100	t	f
1788	298	Jul	2026	100	t	f
1789	298	Ago	2026	100	t	f
1790	299	Mar	2026	100	t	f
1791	299	Abr	2026	100	t	f
1792	299	Mai	2026	100	t	f
1793	299	Jun	2026	100	t	f
1794	299	Jul	2026	100	t	f
1795	299	Ago	2026	100	t	f
1796	300	Mar	2026	100	t	f
1797	300	Abr	2026	100	t	f
1798	300	Mai	2026	100	t	f
1799	300	Jun	2026	100	t	f
1800	300	Jul	2026	100	t	f
1801	300	Ago	2026	100	t	f
1802	301	Mar	2026	100	t	f
1803	301	Abr	2026	100	t	f
1804	301	Mai	2026	100	t	f
1805	301	Jun	2026	100	t	f
1806	301	Jul	2026	100	t	f
1807	301	Ago	2026	100	t	f
1808	302	Mar	2026	100	t	f
1809	302	Abr	2026	100	t	f
1810	302	Mai	2026	100	t	f
1811	302	Jun	2026	100	t	f
1812	302	Jul	2026	100	t	f
1813	302	Ago	2026	100	t	f
1814	303	Mar	2026	100	t	f
1815	303	Abr	2026	100	t	f
1816	303	Mai	2026	100	t	f
1817	303	Jun	2026	100	t	f
1818	303	Jul	2026	100	t	f
1819	303	Ago	2026	100	t	f
1820	304	Mar	2026	100	t	f
1821	304	Abr	2026	100	t	f
1822	304	Mai	2026	100	t	f
1823	304	Jun	2026	100	t	f
1824	304	Jul	2026	100	t	f
1825	304	Ago	2026	100	t	f
1826	305	Mar	2026	100	t	f
1827	305	Abr	2026	100	t	f
1828	305	Mai	2026	100	t	f
1829	305	Jun	2026	100	t	f
1830	305	Jul	2026	100	t	f
1831	305	Ago	2026	100	t	f
1832	306	Mar	2026	100	t	f
1833	306	Abr	2026	100	t	f
1834	306	Mai	2026	100	t	f
1835	306	Jun	2026	100	t	f
1836	306	Jul	2026	100	t	f
1837	306	Ago	2026	100	t	f
1838	307	Mar	2026	100	t	f
1839	307	Abr	2026	100	t	f
1840	307	Mai	2026	100	t	f
1841	307	Jun	2026	100	t	f
1842	307	Jul	2026	100	t	f
1843	307	Ago	2026	100	t	f
1844	308	Mar	2026	100	t	f
1845	308	Abr	2026	100	t	f
1846	308	Mai	2026	100	t	f
1847	308	Jun	2026	100	t	f
1848	308	Jul	2026	100	t	f
1849	308	Ago	2026	100	t	f
1850	309	Mar	2026	100	t	f
1851	309	Abr	2026	100	t	f
1852	309	Mai	2026	100	t	f
1853	309	Jun	2026	100	t	f
1854	309	Jul	2026	100	t	f
1855	309	Ago	2026	100	t	f
1856	310	Mar	2026	100	t	f
1857	310	Abr	2026	100	t	f
1858	310	Mai	2026	100	t	f
1859	310	Jun	2026	100	t	f
1860	310	Jul	2026	100	t	f
1861	310	Ago	2026	100	t	f
1862	311	Mar	2026	100	t	f
1863	311	Abr	2026	100	t	f
1864	311	Mai	2026	100	t	f
1865	311	Jun	2026	0	t	f
1866	311	Jul	2026	0	t	f
1867	311	Ago	2026	0	t	f
1868	312	Mar	2026	100	t	f
1869	312	Abr	2026	100	t	f
1870	312	Mai	2026	100	t	f
1871	312	Jun	2026	100	t	f
1872	312	Jul	2026	100	t	f
1873	312	Ago	2026	100	t	f
1874	313	Mar	2026	100	t	f
1875	313	Abr	2026	100	t	f
1876	313	Mai	2026	100	t	f
1877	313	Jun	2026	100	t	f
1878	313	Jul	2026	100	t	f
1879	313	Ago	2026	100	t	f
1880	314	Mar	2026	100	t	f
1881	314	Abr	2026	100	t	f
1882	314	Mai	2026	100	t	f
1883	314	Jun	2026	0	t	f
1884	314	Jul	2026	0	t	f
1885	314	Ago	2026	0	t	f
1886	315	Mar	2026	100	t	f
1887	315	Abr	2026	100	t	f
1888	315	Mai	2026	100	t	f
1889	315	Jun	2026	100	t	f
1890	315	Jul	2026	100	t	f
1891	315	Ago	2026	100	t	f
1892	316	Mar	2026	100	t	f
1893	316	Abr	2026	100	t	f
1894	316	Mai	2026	100	t	f
1895	316	Jun	2026	100	t	f
1896	316	Jul	2026	100	t	f
1897	316	Ago	2026	100	t	f
1898	317	Mar	2026	100	t	f
1899	317	Abr	2026	100	t	f
1900	317	Mai	2026	100	t	f
1901	317	Jun	2026	100	t	f
1902	317	Jul	2026	100	t	f
1903	317	Ago	2026	100	t	f
1904	318	Mar	2026	100	t	f
1905	318	Abr	2026	100	t	f
1906	318	Mai	2026	100	t	f
1907	318	Jun	2026	100	t	f
1908	318	Jul	2026	100	t	f
1909	318	Ago	2026	100	t	f
1910	319	Mar	2026	100	t	f
1911	319	Abr	2026	100	t	f
1912	319	Mai	2026	100	t	f
1913	319	Jun	2026	100	t	f
1914	319	Jul	2026	100	t	f
1915	319	Ago	2026	100	t	f
1916	320	Mar	2026	100	t	f
1917	320	Abr	2026	100	t	f
1918	320	Mai	2026	100	t	f
1919	320	Jun	2026	100	t	f
1920	320	Jul	2026	100	t	f
1921	320	Ago	2026	100	t	f
1922	321	Mar	2026	100	t	f
1923	321	Abr	2026	100	t	f
1924	321	Mai	2026	100	t	f
1925	321	Jun	2026	100	t	f
1926	321	Jul	2026	100	t	f
1927	321	Ago	2026	100	t	f
1928	322	Mar	2026	100	t	f
1929	322	Abr	2026	100	t	f
1930	322	Mai	2026	100	t	f
1931	322	Jun	2026	100	t	f
1932	322	Jul	2026	100	t	f
1933	322	Ago	2026	100	t	f
1934	323	Mar	2026	100	t	f
1935	323	Abr	2026	100	t	f
1936	323	Mai	2026	100	t	f
1937	323	Jun	2026	100	t	f
1938	323	Jul	2026	100	t	f
1939	323	Ago	2026	100	t	f
1940	324	Mar	2026	100	t	f
1941	324	Abr	2026	100	t	f
1942	324	Mai	2026	100	t	f
1943	324	Jun	2026	100	t	f
1944	324	Jul	2026	100	t	f
1945	324	Ago	2026	100	t	f
1946	325	Mar	2026	100	t	f
1947	325	Abr	2026	100	t	f
1948	325	Mai	2026	100	t	f
1949	325	Jun	2026	100	t	f
1950	325	Jul	2026	100	t	f
1951	325	Ago	2026	100	t	f
1952	326	Mar	2026	100	t	f
1953	326	Abr	2026	100	t	f
1954	326	Mai	2026	100	t	f
1955	326	Jun	2026	100	t	f
1956	326	Jul	2026	100	t	f
1957	326	Ago	2026	100	t	f
1958	327	Mar	2026	100	t	f
1959	327	Abr	2026	100	t	f
1960	327	Mai	2026	100	t	f
1961	327	Jun	2026	100	t	f
1962	327	Jul	2026	100	t	f
1963	327	Ago	2026	100	t	f
1964	328	Mar	2026	100	t	f
1965	328	Abr	2026	100	t	f
1966	328	Mai	2026	100	t	f
1967	328	Jun	2026	100	t	f
1968	328	Jul	2026	100	t	f
1969	328	Ago	2026	100	t	f
1970	329	Mar	2026	100	t	f
1971	329	Abr	2026	100	t	f
1972	329	Mai	2026	100	t	f
1973	329	Jun	2026	100	t	f
1974	329	Jul	2026	100	t	f
1975	329	Ago	2026	100	t	f
1976	330	Mar	2026	100	t	f
1977	330	Abr	2026	100	t	f
1978	330	Mai	2026	100	t	f
1979	330	Jun	2026	100	t	f
1980	330	Jul	2026	100	t	f
1981	330	Ago	2026	100	t	f
1982	331	Mar	2026	100	t	f
1983	331	Abr	2026	100	t	f
1984	331	Mai	2026	100	t	f
1985	331	Jun	2026	100	t	f
1986	331	Jul	2026	100	t	f
1987	331	Ago	2026	100	t	f
1988	332	Mar	2026	100	t	f
1989	332	Abr	2026	100	t	f
1990	332	Mai	2026	100	t	f
1991	332	Jun	2026	100	t	f
1992	332	Jul	2026	100	t	f
1993	332	Ago	2026	100	t	f
1994	333	Mar	2026	100	t	f
1995	333	Abr	2026	100	t	f
1996	333	Mai	2026	100	t	f
1997	333	Jun	2026	100	t	f
1998	333	Jul	2026	100	t	f
1999	333	Ago	2026	100	t	f
2000	334	Mar	2026	100	t	f
2001	334	Abr	2026	100	t	f
2002	334	Mai	2026	100	t	f
2003	334	Jun	2026	100	t	f
2004	334	Jul	2026	100	t	f
2005	334	Ago	2026	100	t	f
2006	335	Mar	2026	100	t	f
2007	335	Abr	2026	100	t	f
2008	335	Mai	2026	100	t	f
2009	335	Jun	2026	100	t	f
2010	335	Jul	2026	100	t	f
2011	335	Ago	2026	100	t	f
2012	336	Mar	2026	100	t	f
2013	336	Abr	2026	100	t	f
2014	336	Mai	2026	100	t	f
2015	336	Jun	2026	100	t	f
2016	336	Jul	2026	100	t	f
2017	336	Ago	2026	100	t	f
2018	337	Mar	2026	100	t	f
2019	337	Abr	2026	100	t	f
2020	337	Mai	2026	100	t	f
2021	337	Jun	2026	100	t	f
2022	337	Jul	2026	100	t	f
2023	337	Ago	2026	100	t	f
2024	338	Mar	2026	100	t	f
2025	338	Abr	2026	100	t	f
2026	338	Mai	2026	100	t	f
2027	338	Jun	2026	100	t	f
2028	338	Jul	2026	100	t	f
2029	338	Ago	2026	100	t	f
2030	339	Mar	2026	100	t	f
2031	339	Abr	2026	100	t	f
2032	339	Mai	2026	100	t	f
2033	339	Jun	2026	100	t	f
2034	339	Jul	2026	100	t	f
2035	339	Ago	2026	100	t	f
2036	340	Mar	2026	100	t	f
2037	340	Abr	2026	100	t	f
2038	340	Mai	2026	100	t	f
2039	340	Jun	2026	100	t	f
2040	340	Jul	2026	100	t	f
2041	340	Ago	2026	100	t	f
2042	341	Mar	2026	100	t	f
2043	341	Abr	2026	100	t	f
2044	341	Mai	2026	100	t	f
2045	341	Jun	2026	100	t	f
2046	341	Jul	2026	100	t	f
2047	341	Ago	2026	100	t	f
2048	342	Mar	2026	100	t	f
2049	342	Abr	2026	100	t	f
2050	342	Mai	2026	100	t	f
2051	342	Jun	2026	100	t	f
2052	342	Jul	2026	100	t	f
2053	342	Ago	2026	100	t	f
2054	343	Mar	2026	100	t	f
2055	343	Abr	2026	100	t	f
2056	343	Mai	2026	100	t	f
2057	343	Jun	2026	100	t	f
2058	343	Jul	2026	100	t	f
2059	343	Ago	2026	100	t	f
2060	344	Mar	2026	100	t	f
2061	344	Abr	2026	100	t	f
2062	344	Mai	2026	100	t	f
2063	344	Jun	2026	100	t	f
2064	344	Jul	2026	100	t	f
2065	344	Ago	2026	100	t	f
2066	345	Mar	2026	100	t	f
2067	345	Abr	2026	100	t	f
2068	345	Mai	2026	100	t	f
2069	345	Jun	2026	100	t	f
2070	345	Jul	2026	100	t	f
2071	345	Ago	2026	100	t	f
2072	346	Mar	2026	100	t	f
2073	346	Abr	2026	100	t	f
2074	346	Mai	2026	100	t	f
2075	346	Jun	2026	100	t	f
2076	346	Jul	2026	100	t	f
2077	346	Ago	2026	100	t	f
2078	347	Mar	2026	100	t	f
2079	347	Abr	2026	100	t	f
2080	347	Mai	2026	100	t	f
2081	347	Jun	2026	100	t	f
2082	347	Jul	2026	100	t	f
2083	347	Ago	2026	100	t	f
2084	348	Mar	2026	100	t	f
2085	348	Abr	2026	100	t	f
2086	348	Mai	2026	100	t	f
2087	348	Jun	2026	100	t	f
2088	348	Jul	2026	100	t	f
2089	348	Ago	2026	100	t	f
2090	349	Mar	2026	100	t	f
2091	349	Abr	2026	100	t	f
2092	349	Mai	2026	100	t	f
2093	349	Jun	2026	100	t	f
2094	349	Jul	2026	100	t	f
2095	349	Ago	2026	100	t	f
2096	350	Mar	2026	100	t	f
2097	350	Abr	2026	100	t	f
2098	350	Mai	2026	100	t	f
2099	350	Jun	2026	100	t	f
2100	350	Jul	2026	100	t	f
2101	350	Ago	2026	100	t	f
2102	351	Mar	2026	100	t	f
2103	351	Abr	2026	100	t	f
2104	351	Mai	2026	100	t	f
2105	351	Jun	2026	100	t	f
2106	351	Jul	2026	100	t	f
2107	351	Ago	2026	100	t	f
2108	352	Mar	2026	100	t	f
2109	352	Abr	2026	100	t	f
2110	352	Mai	2026	100	t	f
2111	352	Jun	2026	100	t	f
2112	352	Jul	2026	100	t	f
2113	352	Ago	2026	100	t	f
2114	353	Mar	2026	100	t	f
2115	353	Abr	2026	100	t	f
2116	353	Mai	2026	100	t	f
2117	353	Jun	2026	100	t	f
2118	353	Jul	2026	100	t	f
2119	353	Ago	2026	100	t	f
2120	354	Mar	2026	50	t	f
2121	354	Abr	2026	50	t	f
2122	354	Mai	2026	50	t	f
2123	354	Jun	2026	50	t	f
2124	354	Jul	2026	50	t	f
2125	354	Ago	2026	50	t	f
2126	355	Mar	2026	100	t	f
2127	355	Abr	2026	100	t	f
2128	355	Mai	2026	100	t	f
2129	355	Jun	2026	100	t	f
2130	355	Jul	2026	100	t	f
2131	355	Ago	2026	100	t	f
2132	356	Mar	2026	100	t	f
2133	356	Abr	2026	100	t	f
2134	356	Mai	2026	100	t	f
2135	356	Jun	2026	100	t	f
2136	356	Jul	2026	100	t	f
2137	356	Ago	2026	100	t	f
2138	357	Mar	2026	100	t	f
2139	357	Abr	2026	100	t	f
2140	357	Mai	2026	100	t	f
2141	357	Jun	2026	100	t	f
2142	357	Jul	2026	100	t	f
2143	357	Ago	2026	100	t	f
2144	107	Jun	2026	0	t	f
2145	107	Jul	2026	0	t	f
2146	107	Ago	2026	0	t	f
2147	358	Mar	2026	100	t	f
2148	358	Abr	2026	100	t	f
2149	358	Mai	2026	100	t	f
2150	358	Jun	2026	100	t	f
2151	358	Jul	2026	100	t	f
2152	358	Ago	2026	100	t	f
2153	359	Mar	2026	100	t	f
2154	359	Abr	2026	100	t	f
2155	359	Mai	2026	100	t	f
2156	359	Jun	2026	100	t	f
2157	359	Jul	2026	100	t	f
2158	359	Ago	2026	100	t	f
2159	360	Mar	2026	100	t	f
2160	360	Abr	2026	100	t	f
2161	360	Mai	2026	100	t	f
2162	360	Jun	2026	100	t	f
2163	360	Jul	2026	100	t	f
2164	360	Ago	2026	100	t	f
2165	361	Mar	2026	100	t	f
2166	361	Abr	2026	100	t	f
2167	361	Mai	2026	100	t	f
2168	361	Jun	2026	100	t	f
2169	361	Jul	2026	100	t	f
2170	361	Ago	2026	100	t	f
2171	362	Mar	2026	100	t	f
2172	362	Abr	2026	100	t	f
2173	362	Mai	2026	100	t	f
2174	362	Jun	2026	100	t	f
2175	362	Jul	2026	100	t	f
2176	362	Ago	2026	100	t	f
2177	363	Mar	2026	100	t	f
2178	363	Abr	2026	100	t	f
2179	363	Mai	2026	100	t	f
2180	363	Jun	2026	100	t	f
2181	363	Jul	2026	100	t	f
2182	363	Ago	2026	100	t	f
2183	364	Mar	2026	100	t	f
2184	364	Abr	2026	100	t	f
2185	364	Mai	2026	100	t	f
2186	364	Jun	2026	100	t	f
2187	364	Jul	2026	100	t	f
2188	364	Ago	2026	100	t	f
2189	365	Mar	2026	100	t	f
2190	365	Abr	2026	100	t	f
2191	365	Mai	2026	100	t	f
2192	365	Jun	2026	100	t	f
2193	365	Jul	2026	100	t	f
2194	365	Ago	2026	100	t	f
2195	366	Mar	2026	90	t	f
2196	366	Abr	2026	50	t	f
2197	366	Mai	2026	75	t	f
2198	366	Jun	2026	0	t	f
2199	366	Jul	2026	0	t	f
2200	366	Ago	2026	0	t	f
2201	367	Mar	2026	10	t	f
2202	367	Abr	2026	0	t	f
2203	367	Mai	2026	0	t	f
2204	367	Jun	2026	0	t	f
2205	367	Jul	2026	0	t	f
2206	367	Ago	2026	0	t	f
2207	368	Mar	2026	100	t	f
2208	368	Abr	2026	100	t	f
2209	368	Mai	2026	100	t	f
2210	368	Jun	2026	100	t	f
2211	368	Jul	2026	100	t	f
2212	368	Ago	2026	100	t	f
2213	369	Mar	2026	100	t	f
2214	369	Abr	2026	100	t	f
2215	369	Mai	2026	100	t	f
2216	369	Jun	2026	100	t	f
2217	369	Jul	2026	100	t	f
2218	369	Ago	2026	100	t	f
2219	370	Mar	2026	90	t	f
2220	370	Abr	2026	25	t	f
2221	370	Mai	2026	0	t	f
2222	370	Jun	2026	0	t	f
2223	370	Jul	2026	43	t	f
2224	370	Ago	2026	50	t	f
2225	168	Mar	2026	100	t	f
2226	168	Abr	2026	100	t	f
2227	168	Mai	2026	100	t	f
2228	168	Jun	2026	100	t	f
2229	168	Jul	2026	100	t	f
2230	168	Ago	2026	100	t	f
2231	371	Mar	2026	100	t	f
2232	371	Abr	2026	100	t	f
2233	371	Mai	2026	100	t	f
2234	371	Jun	2026	100	t	f
2235	371	Jul	2026	0	t	f
2236	371	Ago	2026	0	t	f
2237	372	Mar	2026	100	t	f
2238	372	Abr	2026	100	t	f
2239	372	Mai	2026	100	t	f
2240	372	Jun	2026	100	t	f
2241	372	Jul	2026	100	t	f
2242	372	Ago	2026	100	t	f
2243	373	Mar	2026	100	t	f
2244	373	Abr	2026	100	t	f
2245	373	Mai	2026	100	t	f
2246	373	Jun	2026	100	t	f
2247	373	Jul	2026	100	t	f
2248	373	Ago	2026	100	t	f
2249	374	Mar	2026	100	t	f
2250	374	Abr	2026	100	t	f
2251	374	Mai	2026	100	t	f
2252	374	Jun	2026	100	t	f
2253	374	Jul	2026	100	t	f
2254	374	Ago	2026	100	t	f
2255	375	Mar	2026	100	t	f
2256	375	Abr	2026	100	t	f
2257	375	Mai	2026	100	t	f
2258	375	Jun	2026	100	t	f
2259	375	Jul	2026	100	t	f
2260	375	Ago	2026	100	t	f
2261	376	Mar	2026	0	t	f
2262	376	Abr	2026	10	t	f
2263	376	Mai	2026	50	t	f
2264	376	Jun	2026	50	t	f
2265	376	Jul	2026	50	t	f
2266	376	Ago	2026	0	t	f
2267	377	Mar	2026	0	t	f
2268	377	Abr	2026	11	t	f
2269	377	Mai	2026	50	t	f
2270	377	Jun	2026	50	t	f
2271	377	Jul	2026	50	t	f
2272	377	Ago	2026	100	t	f
2273	378	Mar	2026	0	t	f
2274	378	Abr	2026	100	t	f
2275	378	Mai	2026	100	t	f
2276	378	Jun	2026	100	t	f
2277	378	Jul	2026	100	t	f
2278	378	Ago	2026	100	t	f
2279	136	Jun	2026	100	t	f
2280	136	Jul	2026	100	t	f
2281	136	Ago	2026	100	t	f
2282	379	Mar	2026	100	t	f
2283	379	Abr	2026	100	t	f
2284	379	Mai	2026	100	t	f
2285	379	Jun	2026	100	t	f
2286	379	Jul	2026	100	t	f
2287	379	Ago	2026	100	t	f
2288	380	Mar	2026	100	t	f
2289	380	Abr	2026	100	t	f
2290	380	Mai	2026	100	t	f
2291	380	Jun	2026	100	t	f
2292	380	Jul	2026	100	t	f
2293	380	Ago	2026	100	t	f
2294	74	Jun	2026	100	t	f
2295	74	Jul	2026	100	t	f
2296	74	Ago	2026	100	t	f
2297	381	Mar	2026	100	t	f
2298	381	Abr	2026	100	t	f
2299	381	Mai	2026	100	t	f
2300	381	Jun	2026	100	t	f
2301	381	Jul	2026	100	t	f
2302	381	Ago	2026	0	t	f
2303	382	Mar	2026	100	t	f
2304	382	Abr	2026	100	t	f
2305	382	Mai	2026	100	t	f
2306	382	Jun	2026	100	t	f
2307	382	Jul	2026	100	t	f
2308	382	Ago	2026	100	t	f
2309	383	Mar	2026	100	t	f
2310	383	Abr	2026	100	t	f
2311	383	Mai	2026	100	t	f
2312	383	Jun	2026	100	t	f
2313	383	Jul	2026	100	t	f
2314	383	Ago	2026	100	t	f
2315	384	Mar	2026	100	t	f
2316	384	Abr	2026	100	t	f
2317	384	Mai	2026	100	t	f
2318	384	Jun	2026	100	t	f
2319	384	Jul	2026	100	t	f
2320	384	Ago	2026	100	t	f
2321	385	Mar	2026	100	t	f
2322	385	Abr	2026	100	t	f
2323	385	Mai	2026	100	t	f
2324	385	Jun	2026	100	t	f
2325	385	Jul	2026	100	t	f
2326	385	Ago	2026	100	t	f
2327	386	Mar	2026	100	t	f
2328	386	Abr	2026	100	t	f
2329	386	Mai	2026	100	t	f
2330	386	Jun	2026	100	t	f
2331	386	Jul	2026	100	t	f
2332	386	Ago	2026	100	t	f
2333	387	Mar	2026	100	t	f
2334	387	Abr	2026	100	t	f
2335	387	Mai	2026	100	t	f
2336	387	Jun	2026	100	t	f
2337	387	Jul	2026	100	t	f
2338	387	Ago	2026	100	t	f
2339	60	Jun	2026	100	t	f
2340	60	Jul	2026	0	t	f
2341	60	Ago	2026	0	t	f
2342	101	Jun	2026	100	t	f
2343	101	Jul	2026	100	t	f
2344	101	Ago	2026	100	t	f
2345	50	Jun	2026	100	t	f
2346	50	Jul	2026	100	t	f
2347	50	Ago	2026	100	t	f
2348	42	Jun	2026	100	t	f
2349	42	Jul	2026	100	t	f
2350	42	Ago	2026	100	t	f
2351	79	Jun	2026	100	t	f
2352	79	Jul	2026	100	t	f
2353	79	Ago	2026	100	t	f
2354	155	Jun	2026	100	t	f
2355	155	Jul	2026	100	t	f
2356	155	Ago	2026	100	t	f
2357	51	Jun	2026	100	t	f
2358	51	Jul	2026	100	t	f
2359	51	Ago	2026	100	t	f
2360	388	Mar	2026	0	t	f
2361	388	Abr	2026	0	t	f
2362	388	Mai	2026	100	t	f
2363	388	Jun	2026	100	t	f
2364	388	Jul	2026	50	t	f
2365	388	Ago	2026	0	t	f
2366	389	Mar	2026	100	t	f
2367	389	Abr	2026	100	t	f
2368	389	Mai	2026	100	t	f
2369	389	Jun	2026	100	t	f
2370	389	Jul	2026	100	t	f
2371	389	Ago	2026	100	t	f
2372	87	Jun	2026	100	t	f
2373	87	Jul	2026	100	t	f
2374	87	Ago	2026	100	t	f
2375	110	Jun	2026	100	t	f
2376	110	Jul	2026	100	t	f
2377	110	Ago	2026	100	t	f
2378	104	Jun	2026	100	t	f
2379	104	Jul	2026	100	t	f
2380	104	Ago	2026	100	t	f
2381	21	Jun	2026	100	t	f
2382	21	Jul	2026	100	t	f
2383	21	Ago	2026	100	t	f
2384	11	Jun	2026	100	t	f
2385	11	Jul	2026	100	t	f
2386	11	Ago	2026	100	t	f
2387	94	Jun	2026	100	t	f
2388	94	Jul	2026	100	t	f
2389	94	Ago	2026	100	t	f
2390	52	Jun	2026	100	t	f
2391	52	Jul	2026	100	t	f
2392	52	Ago	2026	100	t	f
2393	154	Jun	2026	100	t	f
2394	154	Jul	2026	100	t	f
2395	154	Ago	2026	100	t	f
2396	16	Jun	2026	100	t	f
2397	16	Jul	2026	100	t	f
2398	16	Ago	2026	100	t	f
2399	390	Mar	2026	100	t	f
2400	390	Abr	2026	100	t	f
2401	390	Mai	2026	100	t	f
2402	390	Jun	2026	100	t	f
2403	390	Jul	2026	100	t	f
2404	390	Ago	2026	100	t	f
2405	391	Mar	2026	100	t	f
2406	391	Abr	2026	100	t	f
2407	391	Mai	2026	100	t	f
2408	391	Jun	2026	100	t	f
2409	391	Jul	2026	100	t	f
2410	391	Ago	2026	100	t	f
2411	392	Mar	2026	100	t	f
2412	392	Abr	2026	100	t	f
2413	392	Mai	2026	100	t	f
2414	392	Jun	2026	100	t	f
2415	392	Jul	2026	100	t	f
2416	392	Ago	2026	100	t	f
2417	53	Jun	2026	0	t	f
2418	53	Jul	2026	0	t	f
2419	53	Ago	2026	0	t	f
2420	167	Jun	2026	100	t	f
2421	167	Jul	2026	0	t	f
2422	167	Ago	2026	0	t	f
2423	85	Jun	2026	100	t	f
2424	85	Jul	2026	100	t	f
2425	85	Ago	2026	100	t	f
2426	137	Jun	2026	100	t	f
2427	137	Jul	2026	100	t	f
2428	137	Ago	2026	100	t	f
2429	113	Jun	2026	0	t	f
2430	113	Jul	2026	0	t	f
2431	113	Ago	2026	0	t	f
2432	100	Jun	2026	0	t	f
2433	100	Jul	2026	0	t	f
2434	100	Ago	2026	0	t	f
2435	59	Jun	2026	0	t	f
2436	59	Jul	2026	0	t	f
2437	59	Ago	2026	0	t	f
2438	93	Jun	2026	100	t	f
2439	93	Jul	2026	100	t	f
2440	93	Ago	2026	100	t	f
2441	393	Mar	2026	100	t	f
2442	393	Abr	2026	100	t	f
2443	393	Mai	2026	100	t	f
2444	393	Jun	2026	100	t	f
2445	393	Jul	2026	100	t	f
2446	393	Ago	2026	100	t	f
2447	394	Mar	2026	100	t	f
2448	394	Abr	2026	100	t	f
2449	394	Mai	2026	100	t	f
2450	394	Jun	2026	100	t	f
2451	394	Jul	2026	100	t	f
2452	394	Ago	2026	100	t	f
2453	395	Mar	2026	100	t	f
2454	395	Abr	2026	100	t	f
2455	395	Mai	2026	100	t	f
2456	395	Jun	2026	100	t	f
2457	395	Jul	2026	100	t	f
2458	395	Ago	2026	100	t	f
2459	396	Mar	2026	0	t	f
2460	396	Abr	2026	0	t	f
2461	396	Mai	2026	0	t	f
2462	396	Jun	2026	0	t	f
2463	396	Jul	2026	0	t	f
2464	396	Ago	2026	0	t	f
2465	143	Jun	2026	100	t	f
2466	143	Jul	2026	5	t	f
2467	143	Ago	2026	0	t	f
2468	397	Mar	2026	0	t	f
2469	397	Abr	2026	0	t	f
2470	397	Mai	2026	60	t	f
2471	397	Jun	2026	30	t	f
2472	397	Jul	2026	57	t	f
2473	397	Ago	2026	75	t	f
2474	398	Mar	2026	30	t	f
2475	398	Abr	2026	75	t	f
2476	398	Mai	2026	25	t	f
2477	398	Jun	2026	0	t	f
2478	398	Jul	2026	0	t	f
2479	398	Ago	2026	75	t	f
2480	399	Mar	2026	40	t	f
2481	399	Abr	2026	0	t	f
2482	399	Mai	2026	0	t	f
2483	399	Jun	2026	25	t	f
2484	399	Jul	2026	0	t	f
2485	399	Ago	2026	0	t	f
2486	400	Mar	2026	0	t	f
2487	400	Abr	2026	40	t	f
2488	400	Mai	2026	25	t	f
2489	400	Jun	2026	0	t	f
2490	400	Jul	2026	25	t	f
2491	400	Ago	2026	25	t	f
2492	401	Mar	2026	0	t	f
2493	401	Abr	2026	50	t	f
2494	401	Mai	2026	25	t	f
2495	401	Jun	2026	0	t	f
2496	401	Jul	2026	25	t	f
2497	401	Ago	2026	25	t	f
2498	402	Mar	2026	50	t	f
2499	402	Abr	2026	50	t	f
2500	402	Mai	2026	40	t	f
2501	402	Jun	2026	25	t	f
2502	402	Jul	2026	10	t	f
2503	402	Ago	2026	10	t	f
2504	403	Mar	2026	50	t	f
2505	403	Abr	2026	50	t	f
2506	403	Mai	2026	15	t	f
2507	403	Jun	2026	25	t	f
2508	403	Jul	2026	10	t	f
2509	403	Ago	2026	25	t	f
2510	397	Set	2026	3	t	f
2511	192	Set	2026	7	t	f
2512	193	Set	2026	0	t	f
2513	404	Abr	2026	0	t	f
2514	404	Mai	2026	0	t	f
2515	404	Jun	2026	60	t	f
2516	404	Jul	2026	0	t	f
2517	404	Ago	2026	0	t	f
2518	404	Set	2026	0	t	f
2519	396	Set	2026	0	t	f
2520	204	Set	2026	0	t	f
2521	376	Set	2026	0	t	f
2522	377	Set	2026	80	t	f
2523	195	Set	2026	0	t	f
2524	196	Set	2026	0	t	f
2525	363	Set	2026	100	t	f
2526	217	Set	2026	50	t	f
2527	218	Set	2026	50	t	f
2528	216	Set	2026	100	t	f
2529	214	Set	2026	0	t	f
2530	215	Set	2026	0	t	f
2531	211	Set	2026	0	t	f
2532	199	Set	2026	100	t	f
2533	200	Set	2026	0	t	f
2534	189	Set	2026	0	t	f
2535	197	Set	2026	0	t	f
2536	198	Set	2026	0	t	f
2537	170	Set	2026	30	t	f
2538	186	Set	2026	30	t	f
2539	394	Set	2026	100	t	f
2540	395	Set	2026	100	t	f
2541	401	Set	2026	50	t	f
2542	187	Set	2026	50	t	f
2543	181	Set	2026	30	t	f
2544	205	Set	2026	0	t	f
2545	206	Set	2026	0	t	f
2546	405	Abr	2026	0	t	f
2547	405	Mai	2026	0	t	f
2548	405	Jun	2026	100	t	f
2549	405	Jul	2026	100	t	f
2550	405	Ago	2026	100	t	f
2551	405	Set	2026	27	t	f
2552	400	Set	2026	50	t	f
2553	180	Set	2026	20	t	f
2554	366	Set	2026	0	t	f
2555	296	Set	2026	100	t	f
2556	297	Set	2026	100	t	f
2557	298	Set	2026	100	t	f
2558	316	Set	2026	100	t	f
2559	299	Set	2026	100	t	f
2560	300	Set	2026	100	t	f
2561	301	Set	2026	100	t	f
2562	359	Set	2026	100	t	f
2563	303	Set	2026	100	t	f
2564	304	Set	2026	100	t	f
2565	306	Set	2026	100	t	f
2566	305	Set	2026	100	t	f
2567	308	Set	2026	100	t	f
2568	309	Set	2026	100	t	f
2569	310	Set	2026	100	t	f
2570	312	Set	2026	100	t	f
2571	122	Jun	2026	100	t	f
2572	122	Jul	2026	100	t	f
2573	122	Ago	2026	100	t	f
2574	122	Set	2026	100	t	f
2575	147	Jun	2026	100	t	f
2576	147	Jul	2026	100	t	f
2577	147	Ago	2026	100	t	f
2578	147	Set	2026	100	t	f
2579	74	Set	2026	100	t	f
2580	141	Jun	2026	100	t	f
2581	141	Jul	2026	100	t	f
2582	141	Ago	2026	100	t	f
2583	141	Set	2026	100	t	f
2584	128	Jun	2026	100	t	f
2585	128	Jul	2026	100	t	f
2586	128	Ago	2026	100	t	f
2587	128	Set	2026	100	t	f
2588	43	Jun	2026	100	t	f
2589	43	Jul	2026	100	t	f
2590	43	Ago	2026	100	t	f
2591	43	Set	2026	100	t	f
2592	88	Jun	2026	100	t	f
2593	88	Jul	2026	100	t	f
2594	88	Ago	2026	100	t	f
2595	88	Set	2026	100	t	f
2596	83	Jun	2026	100	t	f
2597	83	Jul	2026	100	t	f
2598	83	Ago	2026	100	t	f
2599	83	Set	2026	100	t	f
2600	67	Jun	2026	100	t	f
2601	67	Jul	2026	100	t	f
2602	67	Ago	2026	100	t	f
2603	67	Set	2026	100	t	f
2604	378	Set	2026	100	t	f
2605	406	Abr	2026	100	t	f
2606	406	Mai	2026	100	t	f
2607	406	Jun	2026	100	t	f
2608	406	Jul	2026	100	t	f
2609	406	Ago	2026	100	t	f
2610	406	Set	2026	100	t	f
2611	407	Abr	2026	100	t	f
2612	407	Mai	2026	100	t	f
2613	407	Jun	2026	100	t	f
2614	407	Jul	2026	100	t	f
2615	407	Ago	2026	100	t	f
2616	407	Set	2026	100	t	f
2617	315	Set	2026	100	t	f
2618	368	Set	2026	100	t	f
2619	313	Set	2026	100	t	f
2620	317	Set	2026	100	t	f
2621	369	Set	2026	100	t	f
2622	319	Set	2026	100	t	f
2623	408	Abr	2026	100	t	f
2624	408	Mai	2026	100	t	f
2625	408	Jun	2026	100	t	f
2626	408	Jul	2026	100	t	f
2627	408	Ago	2026	100	t	f
2628	408	Set	2026	100	t	f
2629	320	Set	2026	100	t	f
2630	321	Set	2026	100	t	f
2631	322	Set	2026	100	t	f
2632	323	Set	2026	100	t	f
2633	324	Set	2026	100	t	f
2634	325	Set	2026	100	t	f
2635	326	Set	2026	100	t	f
2636	327	Set	2026	100	t	f
2637	328	Set	2026	100	t	f
2638	329	Set	2026	100	t	f
2639	330	Set	2026	100	t	f
2640	307	Set	2026	100	t	f
2641	362	Set	2026	100	t	f
2642	318	Set	2026	100	t	f
2643	409	Abr	2026	100	t	f
2644	409	Mai	2026	100	t	f
2645	409	Jun	2026	100	t	f
2646	409	Jul	2026	100	t	f
2647	409	Ago	2026	100	t	f
2648	409	Set	2026	100	t	f
2649	410	Abr	2026	100	t	f
2650	410	Mai	2026	100	t	f
2651	410	Jun	2026	100	t	f
2652	410	Jul	2026	100	t	f
2653	410	Ago	2026	100	t	f
2654	410	Set	2026	100	t	f
2655	411	Abr	2026	100	t	f
2656	411	Mai	2026	100	t	f
2657	411	Jun	2026	100	t	f
2658	411	Jul	2026	100	t	f
2659	411	Ago	2026	100	t	f
2660	411	Set	2026	100	t	f
2661	412	Abr	2026	100	t	f
2662	412	Mai	2026	100	t	f
2663	412	Jun	2026	100	t	f
2664	412	Jul	2026	100	t	f
2665	412	Ago	2026	100	t	f
2666	412	Set	2026	100	t	f
2667	413	Abr	2026	100	t	f
2668	413	Mai	2026	100	t	f
2669	413	Jun	2026	100	t	f
2670	413	Jul	2026	100	t	f
2671	413	Ago	2026	100	t	f
2672	413	Set	2026	100	t	f
2673	414	Abr	2026	100	t	f
2674	414	Mai	2026	100	t	f
2675	414	Jun	2026	100	t	f
2676	414	Jul	2026	100	t	f
2677	414	Ago	2026	100	t	f
2678	414	Set	2026	100	t	f
2679	311	Set	2026	0	t	f
2680	415	Abr	2026	0	t	f
2681	415	Mai	2026	60	t	f
2682	415	Jun	2026	0	t	f
2683	415	Jul	2026	0	t	f
2684	415	Ago	2026	0	t	f
2685	415	Set	2026	0	t	f
2686	182	Set	2026	100	t	f
2687	416	Abr	2026	0	t	f
2688	416	Mai	2026	50	t	f
2689	416	Jun	2026	0	t	f
2690	416	Jul	2026	0	t	f
2691	416	Ago	2026	0	t	f
2692	416	Set	2026	0	t	f
2693	398	Set	2026	100	t	f
2694	183	Set	2026	0	t	f
2695	399	Set	2026	0	t	f
2696	417	Abr	2026	0	t	f
2697	417	Mai	2026	15	t	f
2698	417	Jun	2026	50	t	f
2699	417	Jul	2026	28	t	f
2700	417	Ago	2026	0	t	f
2701	417	Set	2026	0	t	f
2702	418	Abr	2026	0	t	f
2703	418	Mai	2026	5	t	f
2704	418	Jun	2026	15	t	f
2705	418	Jul	2026	28	t	f
2706	418	Ago	2026	25	t	f
2707	418	Set	2026	0	t	f
2708	184	Set	2026	0	t	f
2709	212	Set	2026	0	t	f
2710	213	Set	2026	0	t	f
2711	210	Set	2026	20	t	f
2712	419	Abr	2026	0	t	f
2713	419	Mai	2026	40	t	f
2714	419	Jun	2026	0	t	f
2715	419	Jul	2026	0	t	f
2716	419	Ago	2026	0	t	f
2717	419	Set	2026	0	t	f
2718	420	Abr	2026	0	t	f
2719	420	Mai	2026	15	t	f
2720	420	Jun	2026	20	t	f
2721	420	Jul	2026	0	t	f
2722	420	Ago	2026	25	t	f
2723	420	Set	2026	15	t	f
2724	421	Abr	2026	0	t	f
2725	421	Mai	2026	100	t	f
2726	421	Jun	2026	0	t	f
2727	421	Jul	2026	57	t	f
2728	421	Ago	2026	100	t	f
2729	421	Set	2026	50	t	f
2730	422	Abr	2026	0	t	f
2731	422	Mai	2026	45	t	f
2732	422	Jun	2026	0	t	f
2733	422	Jul	2026	0	t	f
2734	422	Ago	2026	0	t	f
2735	422	Set	2026	0	t	f
2736	403	Set	2026	16	t	f
2737	208	Set	2026	16	t	f
2738	209	Set	2026	0	t	f
2739	181	Out	2026	0	t	f
2740	205	Out	2026	0	t	f
2741	206	Out	2026	0	t	f
2742	405	Out	2026	0	t	f
2743	400	Out	2026	25	t	f
2744	180	Out	2026	10	t	f
2745	376	Out	2026	0	t	f
2746	377	Out	2026	50	t	f
2747	195	Out	2026	0	t	f
2748	196	Out	2026	0	t	f
2749	404	Out	2026	0	t	f
2750	396	Out	2026	0	t	f
2751	421	Out	2026	0	t	f
2752	204	Out	2026	0	t	f
2753	422	Out	2026	0	t	f
2754	403	Out	2026	0	t	f
2755	208	Out	2026	0	t	f
2756	401	Out	2026	10	t	f
2757	187	Out	2026	0	t	f
2758	209	Out	2026	0	t	f
2759	171	Set	2026	0	t	f
2760	171	Out	2026	0	t	f
2761	397	Out	2026	0	t	f
2762	420	Out	2026	20	t	f
2763	192	Out	2026	0	t	f
2764	193	Out	2026	0	t	f
2765	370	Set	2026	90	t	f
2766	370	Out	2026	0	t	f
2767	203	Set	2026	0	t	f
2768	203	Out	2026	0	t	f
2769	179	Set	2026	0	t	f
2770	179	Out	2026	0	t	f
2771	182	Out	2026	0	t	f
2772	416	Out	2026	0	t	f
2773	398	Out	2026	0	t	f
2774	418	Out	2026	50	t	f
2775	183	Out	2026	0	t	f
2776	399	Out	2026	0	t	f
2777	417	Out	2026	0	t	f
2778	170	Out	2026	30	t	f
2779	186	Out	2026	50	t	f
2780	366	Out	2026	0	t	f
2781	423	Mai	2026	100	t	f
2782	423	Jun	2026	100	t	f
2783	423	Jul	2026	0	t	f
2784	423	Ago	2026	0	t	f
2785	423	Set	2026	0	t	f
2786	423	Out	2026	0	t	f
2787	402	Set	2026	0	t	f
2788	402	Out	2026	0	t	f
2789	194	Set	2026	50	t	f
2790	194	Out	2026	0	t	f
2791	280	Set	2026	0	t	f
2792	280	Out	2026	0	t	f
2793	282	Set	2026	0	t	f
2794	282	Out	2026	0	t	f
2795	274	Set	2026	0	t	f
2796	274	Out	2026	0	t	f
2797	277	Set	2026	5	t	f
2798	277	Out	2026	5	t	f
2799	281	Set	2026	0	t	f
2800	281	Out	2026	0	t	f
2801	279	Set	2026	25	t	f
2802	279	Out	2026	10	t	f
2803	269	Set	2026	0	t	f
2804	269	Out	2026	0	t	f
2805	143	Set	2026	0	t	f
2806	143	Out	2026	0	t	f
2807	276	Set	2026	0	t	f
2808	276	Out	2026	0	t	f
2809	283	Set	2026	0	t	f
2810	283	Out	2026	0	t	f
2811	207	Set	2026	0	t	f
2812	207	Out	2026	0	t	f
2813	388	Set	2026	0	t	f
2814	388	Out	2026	0	t	f
2815	23	Set	2026	0	t	f
2816	23	Out	2026	0	t	f
2817	424	Mai	2026	100	t	f
2818	424	Jun	2026	100	t	f
2819	424	Jul	2026	0	t	f
2820	424	Ago	2026	0	t	f
2821	424	Set	2026	0	t	f
2822	424	Out	2026	0	t	f
2823	425	Mai	2026	100	t	f
2824	425	Jun	2026	100	t	f
2825	425	Jul	2026	100	t	f
2826	425	Ago	2026	100	t	f
2827	425	Set	2026	100	t	f
2828	425	Out	2026	100	t	f
2829	426	Mai	2026	100	t	f
2830	426	Jun	2026	100	t	f
2831	426	Jul	2026	100	t	f
2832	426	Ago	2026	100	t	f
2833	426	Set	2026	100	t	f
2834	426	Out	2026	100	t	f
2835	427	Mai	2026	100	t	f
2836	427	Jun	2026	100	t	f
2837	427	Jul	2026	100	t	f
2838	427	Ago	2026	100	t	f
2839	427	Set	2026	100	t	f
2840	427	Out	2026	100	t	f
2841	428	Mai	2026	100	t	f
2842	428	Jun	2026	100	t	f
2843	428	Jul	2026	100	t	f
2844	428	Ago	2026	100	t	f
2845	428	Set	2026	100	t	f
2846	428	Out	2026	100	t	f
2847	429	Mai	2026	100	t	f
2848	429	Jun	2026	100	t	f
2849	429	Jul	2026	100	t	f
2850	429	Ago	2026	100	t	f
2851	429	Set	2026	100	t	f
2852	429	Out	2026	100	t	f
2853	430	Mai	2026	100	t	f
2854	430	Jun	2026	100	t	f
2855	430	Jul	2026	100	t	f
2856	430	Ago	2026	100	t	f
2857	430	Set	2026	100	t	f
2858	430	Out	2026	100	t	f
2859	431	Mai	2026	100	t	f
2860	431	Jun	2026	100	t	f
2861	431	Jul	2026	100	t	f
2862	431	Ago	2026	100	t	f
2863	431	Set	2026	100	t	f
2864	431	Out	2026	100	t	f
2865	372	Set	2026	100	t	f
2866	372	Out	2026	100	t	f
2867	371	Set	2026	0	t	f
2868	371	Out	2026	0	t	f
2869	432	Mai	2026	100	t	f
2870	432	Jun	2026	100	t	f
2871	432	Jul	2026	100	t	f
2872	432	Ago	2026	100	t	f
2873	432	Set	2026	100	t	f
2874	432	Out	2026	100	t	f
2875	190	Set	2026	0	t	f
2876	190	Out	2026	0	t	f
2877	374	Set	2026	100	t	f
2878	374	Out	2026	100	t	f
2879	375	Set	2026	100	t	f
2880	375	Out	2026	100	t	f
2881	433	Mai	2026	100	t	f
2882	433	Jun	2026	50	t	f
2883	433	Jul	2026	100	t	f
2884	433	Ago	2026	100	t	f
2885	433	Set	2026	100	t	f
2886	433	Out	2026	100	t	f
2887	373	Set	2026	100	t	f
2888	373	Out	2026	100	t	f
2889	275	Set	2026	0	t	f
2890	275	Out	2026	0	t	f
2891	434	Mai	2026	100	t	f
2892	434	Jun	2026	100	t	f
2893	434	Jul	2026	100	t	f
2894	434	Ago	2026	70	t	f
2895	434	Set	2026	0	t	f
2896	434	Out	2026	0	t	f
2897	435	Mai	2026	10	t	f
2898	435	Jun	2026	10	t	f
2899	435	Jul	2026	10	t	f
2900	435	Ago	2026	10	t	f
2901	435	Set	2026	0	t	f
2902	435	Out	2026	0	t	f
2903	436	Mai	2026	40	t	f
2904	436	Jun	2026	10	t	f
2905	436	Jul	2026	10	t	f
2906	436	Ago	2026	0	t	f
2907	436	Set	2026	0	t	f
2908	436	Out	2026	0	t	f
2909	437	Mai	2026	0	t	f
2910	437	Jun	2026	0	t	f
2911	437	Jul	2026	10	t	f
2912	437	Ago	2026	30	t	f
2913	437	Set	2026	50	t	f
2914	437	Out	2026	60	t	f
2915	438	Mai	2026	50	t	f
2916	438	Jun	2026	80	t	f
2917	438	Jul	2026	70	t	f
2918	438	Ago	2026	60	t	f
2919	438	Set	2026	50	t	f
2920	438	Out	2026	40	t	f
2921	175	Set	2026	10	t	f
2922	175	Out	2026	10	t	f
2923	439	Mai	2026	70	t	f
2924	439	Jun	2026	10	t	f
2925	439	Jul	2026	50	t	f
2926	439	Ago	2026	40	t	f
2927	439	Set	2026	10	t	f
2928	439	Out	2026	10	t	f
2929	440	Mai	2026	20	t	f
2930	440	Jun	2026	50	t	f
2931	440	Jul	2026	20	t	f
2932	440	Ago	2026	20	t	f
2933	440	Set	2026	10	t	f
2934	440	Out	2026	10	t	f
2935	441	Mai	2026	0	t	f
2936	441	Jun	2026	0	t	f
2937	441	Jul	2026	10	t	f
2938	441	Ago	2026	0	t	f
2939	441	Set	2026	0	t	f
2940	441	Out	2026	0	t	f
2941	442	Mai	2026	100	t	f
2942	442	Jun	2026	100	t	f
2943	442	Jul	2026	100	t	f
2944	442	Ago	2026	90	t	f
2945	442	Set	2026	90	t	f
2946	442	Out	2026	90	t	f
2947	443	Mai	2026	80	t	f
2948	443	Jun	2026	10	t	f
2949	443	Jul	2026	0	t	f
2950	443	Ago	2026	0	t	f
2951	443	Set	2026	0	t	f
2952	443	Out	2026	0	t	f
2953	444	Mai	2026	10	t	f
2954	444	Jun	2026	80	t	f
2955	444	Jul	2026	50	t	f
2956	444	Ago	2026	0	t	f
2957	444	Set	2026	0	t	f
2958	444	Out	2026	0	t	f
2959	445	Mai	2026	10	t	f
2960	445	Jun	2026	10	t	f
2961	445	Jul	2026	50	t	f
2962	445	Ago	2026	100	t	f
2963	445	Set	2026	100	t	f
2964	445	Out	2026	100	t	f
2965	446	Mai	2026	100	t	f
2966	446	Jun	2026	100	t	f
2967	446	Jul	2026	14	t	f
2968	446	Ago	2026	0	t	f
2969	446	Set	2026	0	t	f
2970	446	Out	2026	0	t	f
2971	447	Mai	2026	100	t	f
2972	447	Jun	2026	100	t	f
2973	447	Jul	2026	100	t	f
2974	447	Ago	2026	100	t	f
2975	447	Set	2026	100	t	f
2976	447	Out	2026	100	t	f
2977	448	Mai	2026	0	t	f
2978	448	Jun	2026	10	t	f
2979	448	Jul	2026	0	t	f
2980	448	Ago	2026	0	t	f
2981	448	Set	2026	0	t	f
2982	448	Out	2026	0	t	f
2983	449	Mai	2026	100	t	f
2984	449	Jun	2026	0	t	f
2985	449	Jul	2026	0	t	f
2986	449	Ago	2026	0	t	f
2987	449	Set	2026	0	t	f
2988	449	Out	2026	0	t	f
2989	450	Mai	2026	0	t	f
2990	450	Jun	2026	0	t	f
2991	450	Jul	2026	10	t	f
2992	450	Ago	2026	0	t	f
2993	450	Set	2026	0	t	f
2994	450	Out	2026	0	t	f
2995	451	Mai	2026	0	t	f
2996	451	Jun	2026	50	t	f
2997	451	Jul	2026	90	t	f
2998	451	Ago	2026	100	t	f
2999	451	Set	2026	100	t	f
3000	451	Out	2026	100	t	f
3001	452	Mai	2026	0	t	f
3002	452	Jun	2026	40	t	f
3003	452	Jul	2026	0	t	f
3004	452	Ago	2026	0	t	f
3005	452	Set	2026	0	t	f
3006	452	Out	2026	0	t	f
3007	453	Mai	2026	100	t	f
3008	453	Jun	2026	50	t	f
3009	453	Jul	2026	30	t	f
3010	453	Ago	2026	0	t	f
3011	453	Set	2026	0	t	f
3012	453	Out	2026	0	t	f
3013	454	Mai	2026	0	t	f
3014	454	Jun	2026	50	t	f
3015	454	Jul	2026	20	t	f
3016	454	Ago	2026	10	t	f
3017	454	Set	2026	10	t	f
3018	454	Out	2026	10	t	f
3019	455	Mai	2026	0	t	f
3020	455	Jun	2026	100	t	f
3021	455	Jul	2026	100	t	f
3022	455	Ago	2026	100	t	f
3023	455	Set	2026	100	t	f
3024	455	Out	2026	100	t	f
3025	188	Set	2026	0	t	f
3026	188	Out	2026	0	t	f
3027	456	Mai	2026	0	t	f
3028	456	Jun	2026	100	t	f
3029	456	Jul	2026	100	t	f
3030	456	Ago	2026	100	t	f
3031	456	Set	2026	100	t	f
3032	456	Out	2026	100	t	f
3033	457	Mai	2026	0	t	f
3034	457	Jun	2026	100	t	f
3035	457	Jul	2026	100	t	f
3036	457	Ago	2026	100	t	f
3037	457	Set	2026	100	t	f
3038	457	Out	2026	100	t	f
3039	458	Mai	2026	0	t	f
3040	458	Jun	2026	100	t	f
3041	458	Jul	2026	100	t	f
3042	458	Ago	2026	100	t	f
3043	458	Set	2026	100	t	f
3044	458	Out	2026	100	t	f
3045	459	Mai	2026	0	t	f
3046	459	Jun	2026	40	t	f
3047	459	Jul	2026	0	t	f
3048	459	Ago	2026	0	t	f
3049	459	Set	2026	0	t	f
3050	459	Out	2026	0	t	f
3051	216	Out	2026	100	t	f
3052	214	Out	2026	0	t	f
3053	215	Out	2026	0	t	f
3054	363	Out	2026	0	t	f
3055	197	Out	2026	0	t	f
3056	198	Out	2026	0	t	f
3057	199	Out	2026	0	t	f
3058	200	Out	2026	0	t	f
3059	189	Out	2026	0	t	f
3060	211	Out	2026	0	t	f
3061	414	Out	2026	100	t	f
3062	413	Out	2026	100	t	f
3063	246	Set	2026	100	t	f
3064	246	Out	2026	100	t	f
3065	364	Set	2026	100	t	f
3066	364	Out	2026	100	t	f
3067	354	Set	2026	50	t	f
3068	354	Out	2026	50	t	f
3069	247	Set	2026	50	t	f
3070	247	Out	2026	50	t	f
3071	393	Set	2026	100	t	f
3072	393	Out	2026	0	t	f
3073	87	Set	2026	100	t	f
3074	87	Out	2026	100	t	f
3075	394	Out	2026	100	t	f
3076	110	Set	2026	100	t	f
3077	110	Out	2026	100	t	f
3078	104	Set	2026	100	t	f
3079	104	Out	2026	100	t	f
3080	21	Set	2026	100	t	f
3081	21	Out	2026	100	t	f
3082	11	Set	2026	100	t	f
3083	11	Out	2026	100	t	f
3084	94	Set	2026	100	t	f
3085	94	Out	2026	100	t	f
3086	52	Set	2026	100	t	f
3087	52	Out	2026	100	t	f
3088	395	Out	2026	100	t	f
3089	249	Set	2026	100	t	f
3090	249	Out	2026	100	t	f
3091	154	Set	2026	100	t	f
3092	154	Out	2026	100	t	f
3093	16	Set	2026	100	t	f
3094	16	Out	2026	100	t	f
3095	390	Set	2026	100	t	f
3096	390	Out	2026	100	t	f
3097	391	Set	2026	100	t	f
3098	391	Out	2026	100	t	f
3099	251	Set	2026	100	t	f
3100	251	Out	2026	100	t	f
3101	252	Set	2026	100	t	f
3102	252	Out	2026	100	t	f
3103	383	Set	2026	100	t	f
3104	383	Out	2026	0	t	f
3105	254	Set	2026	100	t	f
3106	254	Out	2026	100	t	f
3107	255	Set	2026	100	t	f
3108	255	Out	2026	100	t	f
3109	256	Set	2026	100	t	f
3110	256	Out	2026	100	t	f
3111	257	Set	2026	100	t	f
3112	257	Out	2026	100	t	f
3113	387	Set	2026	100	t	f
3114	387	Out	2026	0	t	f
3115	385	Set	2026	100	t	f
3116	385	Out	2026	0	t	f
3117	389	Set	2026	100	t	f
3118	389	Out	2026	0	t	f
3119	412	Out	2026	100	t	f
3120	411	Out	2026	100	t	f
3121	410	Out	2026	100	t	f
3122	409	Out	2026	100	t	f
3123	408	Out	2026	100	t	f
3124	407	Out	2026	100	t	f
3125	406	Out	2026	100	t	f
3126	378	Out	2026	100	t	f
3127	369	Out	2026	100	t	f
3128	368	Out	2026	100	t	f
3129	362	Out	2026	100	t	f
3130	359	Out	2026	100	t	f
3131	330	Out	2026	100	t	f
3132	329	Out	2026	100	t	f
3133	328	Out	2026	100	t	f
3134	327	Out	2026	100	t	f
3135	326	Out	2026	100	t	f
3136	325	Out	2026	100	t	f
3137	324	Out	2026	100	t	f
3138	322	Out	2026	100	t	f
3139	321	Out	2026	100	t	f
3140	320	Out	2026	100	t	f
3141	319	Out	2026	100	t	f
3142	317	Out	2026	100	t	f
3143	316	Out	2026	100	t	f
3144	315	Out	2026	100	t	f
3145	313	Out	2026	100	t	f
3146	312	Out	2026	100	t	f
3147	310	Out	2026	100	t	f
3148	309	Out	2026	100	t	f
3149	318	Out	2026	100	t	f
3150	308	Out	2026	100	t	f
3151	307	Out	2026	100	t	f
3152	305	Out	2026	100	t	f
3153	304	Out	2026	100	t	f
3154	301	Out	2026	100	t	f
3155	299	Out	2026	100	t	f
3156	298	Out	2026	100	t	f
3157	297	Out	2026	100	t	f
3158	296	Out	2026	100	t	f
3159	171	Nov	2026	0	t	f
3160	459	Nov	2026	0	t	f
3161	370	Nov	2026	0	t	f
3162	446	Nov	2026	0	t	f
3163	179	Nov	2026	0	t	f
3164	217	Out	2026	0	t	f
3165	217	Nov	2026	0	t	f
3166	218	Out	2026	50	t	f
3167	218	Nov	2026	50	t	f
3168	416	Nov	2026	0	t	f
3169	398	Nov	2026	20	t	f
3170	418	Nov	2026	20	t	f
3171	183	Nov	2026	0	t	f
3172	399	Nov	2026	0	t	f
3173	417	Nov	2026	0	t	f
3174	460	Jun	2026	0	t	f
3175	460	Jul	2026	0	t	f
3176	460	Ago	2026	100	t	f
3177	460	Set	2026	100	t	f
3178	460	Out	2026	0	t	f
3179	460	Nov	2026	0	t	f
3180	422	Nov	2026	0	t	f
3181	403	Nov	2026	0	t	f
3182	208	Nov	2026	0	t	f
3183	461	Jun	2026	100	t	f
3184	461	Jul	2026	0	t	f
3185	461	Ago	2026	0	t	f
3186	461	Set	2026	0	t	f
3187	461	Out	2026	0	t	f
3188	461	Nov	2026	0	t	f
3189	59	Set	2026	0	t	f
3190	59	Out	2026	0	t	f
3191	59	Nov	2026	0	t	f
3192	182	Nov	2026	0	t	f
3193	397	Nov	2026	0	t	f
3194	420	Nov	2026	20	t	f
3195	192	Nov	2026	0	t	f
3196	193	Nov	2026	0	t	f
3197	170	Nov	2026	30	t	f
3198	186	Nov	2026	50	t	f
3199	404	Nov	2026	0	t	f
3200	396	Nov	2026	0	t	f
3201	421	Nov	2026	0	t	f
3202	204	Nov	2026	0	t	f
3203	209	Nov	2026	0	t	f
3204	203	Nov	2026	0	t	f
3205	205	Nov	2026	0	t	f
3206	206	Nov	2026	0	t	f
3207	405	Nov	2026	0	t	f
3208	400	Nov	2026	25	t	f
3209	180	Nov	2026	0	t	f
3210	181	Nov	2026	0	t	f
3211	462	Jun	2026	100	t	f
3212	462	Jul	2026	100	t	f
3213	462	Ago	2026	100	t	f
3214	462	Set	2026	100	t	f
3215	462	Out	2026	100	t	f
3216	462	Nov	2026	0	t	f
3217	401	Nov	2026	10	t	f
3218	187	Nov	2026	0	t	f
3219	463	Jun	2026	100	t	f
3220	463	Jul	2026	100	t	f
3221	463	Ago	2026	100	t	f
3222	463	Set	2026	0	t	f
3223	463	Out	2026	0	t	f
3224	463	Nov	2026	0	t	f
3225	113	Set	2026	0	t	f
3226	113	Out	2026	0	t	f
3227	113	Nov	2026	0	t	f
3228	464	Jun	2026	100	t	f
3229	464	Jul	2026	100	t	f
3230	464	Ago	2026	100	t	f
3231	464	Set	2026	0	t	f
3232	464	Out	2026	0	t	f
3233	464	Nov	2026	0	t	f
3234	100	Set	2026	0	t	f
3235	100	Out	2026	0	t	f
3236	100	Nov	2026	0	t	f
3258	464	Abr	2026	100	t	f
3259	464	Mar	2026	100	t	f
3260	463	Abr	2026	100	t	f
3261	463	Mar	2026	100	t	f
3262	463	Fev	2026	100	t	f
3263	464	Fev	2026	100	t	f
3264	463	Mai	2026	100	t	f
3265	464	Mai	2026	100	t	f
3266	282	Nov	2026	0	t	f
3267	281	Nov	2026	10	t	f
3268	465	Jun	2026	100	t	f
3269	465	Jul	2026	100	t	f
3270	465	Ago	2026	100	t	f
3271	465	Set	2026	0	t	f
3272	465	Out	2026	0	t	f
3273	465	Nov	2026	0	t	f
3274	466	Jun	2026	100	t	f
3275	466	Jul	2026	100	t	f
3276	466	Ago	2026	100	t	f
3277	466	Set	2026	0	t	f
3278	466	Out	2026	0	t	f
3279	466	Nov	2026	0	t	f
3280	364	Nov	2026	100	t	f
3281	246	Nov	2026	0	t	f
3282	275	Nov	2026	0	t	f
3283	434	Nov	2026	0	t	f
3284	467	Jun	2026	100	t	f
3285	467	Jul	2026	100	t	f
3286	467	Ago	2026	100	t	f
3287	467	Set	2026	100	t	f
3288	467	Out	2026	100	t	f
3289	467	Nov	2026	100	t	f
3290	468	Jun	2026	0	t	f
3291	468	Jul	2026	100	t	f
3292	468	Ago	2026	100	t	f
3293	468	Set	2026	100	t	f
3294	468	Out	2026	100	t	f
3295	468	Nov	2026	0	t	f
3296	469	Jun	2026	0	t	f
3297	469	Jul	2026	75	t	f
3298	469	Ago	2026	0	t	f
3299	469	Set	2026	0	t	f
3300	469	Out	2026	0	t	f
3301	469	Nov	2026	0	t	f
3302	470	Jun	2026	0	t	f
3303	470	Jul	2026	75	t	f
3304	470	Ago	2026	25	t	f
3305	470	Set	2026	0	t	f
3306	470	Out	2026	0	t	f
3307	470	Nov	2026	0	t	f
3308	471	Jun	2026	0	t	f
3309	471	Jul	2026	50	t	f
3310	471	Ago	2026	100	t	f
3311	471	Set	2026	100	t	f
3312	471	Out	2026	0	t	f
3313	471	Nov	2026	0	t	f
3314	472	Jun	2026	0	t	f
3315	472	Jul	2026	28	t	f
3316	472	Ago	2026	70	t	f
3317	472	Set	2026	70	t	f
3318	472	Out	2026	100	t	f
3319	472	Nov	2026	100	t	f
3320	473	Jun	2026	0	t	f
3321	473	Jul	2026	70	t	f
3322	473	Ago	2026	75	t	f
3323	473	Set	2026	68	t	f
3324	473	Out	2026	50	t	f
3325	473	Nov	2026	50	t	f
3326	474	Jun	2026	0	t	f
3327	474	Jul	2026	43	t	f
3328	474	Ago	2026	50	t	f
3329	474	Set	2026	10	t	f
3330	474	Out	2026	0	t	f
3331	474	Nov	2026	0	t	f
3332	210	Out	2026	20	t	f
3333	210	Nov	2026	30	t	f
3334	201	Set	2026	0	t	f
3335	201	Out	2026	0	t	f
3336	201	Nov	2026	0	t	f
3337	202	Set	2026	0	t	f
3338	202	Out	2026	0	t	f
3339	202	Nov	2026	0	t	f
3340	475	Jun	2026	0	t	f
3341	475	Jul	2026	50	t	f
3342	475	Ago	2026	0	t	f
3343	475	Set	2026	0	t	f
3344	475	Out	2026	0	t	f
3345	475	Nov	2026	0	t	f
3346	476	Jun	2026	100	t	f
3347	476	Jul	2026	100	t	f
3348	476	Ago	2026	100	t	f
3349	476	Set	2026	100	t	f
3350	476	Out	2026	0	t	f
3351	476	Nov	2026	0	t	f
3352	477	Jun	2026	100	t	f
3353	477	Jul	2026	100	t	f
3354	477	Ago	2026	100	t	f
3355	477	Set	2026	100	t	f
3356	477	Out	2026	0	t	f
3357	477	Nov	2026	0	t	f
3358	478	Jun	2026	100	t	f
3359	478	Jul	2026	100	t	f
3360	478	Ago	2026	100	t	f
3361	478	Set	2026	100	t	f
3362	478	Out	2026	0	t	f
3363	478	Nov	2026	0	t	f
3364	479	Jun	2026	100	t	f
3365	479	Jul	2026	100	t	f
3366	479	Ago	2026	100	t	f
3367	479	Set	2026	100	t	f
3368	479	Out	2026	0	t	f
3369	479	Nov	2026	0	t	f
3370	480	Jun	2026	100	t	f
3371	480	Jul	2026	100	t	f
3372	480	Ago	2026	100	t	f
3373	480	Set	2026	100	t	f
3374	480	Out	2026	100	t	f
3375	480	Nov	2026	100	t	f
3376	481	Jun	2026	100	t	f
3377	481	Jul	2026	100	t	f
3378	481	Ago	2026	100	t	f
3379	481	Set	2026	100	t	f
3380	481	Out	2026	100	t	f
3381	481	Nov	2026	0	t	f
3382	482	Jun	2026	100	t	f
3383	482	Jul	2026	100	t	f
3384	482	Ago	2026	100	t	f
3385	482	Set	2026	0	t	f
3386	482	Out	2026	0	t	f
3387	482	Nov	2026	0	t	f
3388	483	Jun	2026	100	t	f
3389	483	Jul	2026	100	t	f
3390	483	Ago	2026	100	t	f
3391	483	Set	2026	100	t	f
3392	483	Out	2026	100	t	f
3393	483	Nov	2026	0	t	f
3394	484	Jun	2026	100	t	f
3395	484	Jul	2026	100	t	f
3396	484	Ago	2026	100	t	f
3397	484	Set	2026	100	t	f
3398	484	Out	2026	100	t	f
3399	484	Nov	2026	100	t	f
3400	85	Set	2026	0	t	f
3401	85	Out	2026	0	t	f
3402	85	Nov	2026	0	t	f
3403	382	Set	2026	100	t	f
3404	382	Out	2026	100	t	f
3405	382	Nov	2026	0	t	f
3406	485	Jun	2026	100	t	f
3407	485	Jul	2026	100	t	f
3408	485	Ago	2026	0	t	f
3409	485	Set	2026	0	t	f
3410	485	Out	2026	0	t	f
3411	485	Nov	2026	0	t	f
3412	486	Jun	2026	100	t	f
3413	486	Jul	2026	100	t	f
3414	486	Ago	2026	100	t	f
3415	486	Set	2026	100	t	f
3416	486	Out	2026	100	t	f
3417	486	Nov	2026	100	t	f
3418	487	Jun	2026	100	t	f
3419	487	Jul	2026	100	t	f
3420	487	Ago	2026	100	t	f
3421	487	Set	2026	100	t	f
3422	487	Out	2026	100	t	f
3423	487	Nov	2026	100	t	f
3424	488	Jun	2026	100	t	f
3425	488	Jul	2026	100	t	f
3426	488	Ago	2026	100	t	f
3427	488	Set	2026	100	t	f
3428	488	Out	2026	100	t	f
3429	488	Nov	2026	100	t	f
3430	489	Jun	2026	100	t	f
3431	489	Jul	2026	100	t	f
3432	489	Ago	2026	100	t	f
3433	489	Set	2026	100	t	f
3434	489	Out	2026	100	t	f
3435	489	Nov	2026	100	t	f
3436	361	Set	2026	0	t	f
3437	361	Out	2026	100	t	f
3438	361	Nov	2026	0	t	f
3439	381	Set	2026	0	t	f
3440	381	Out	2026	0	t	f
3441	381	Nov	2026	0	t	f
3442	490	Jun	2026	0	t	f
3443	490	Jul	2026	45	t	f
3444	490	Ago	2026	45	t	f
3445	490	Set	2026	50	t	f
3446	490	Out	2026	100	t	f
3447	490	Nov	2026	100	t	f
3448	402	Nov	2026	0	t	f
3449	194	Nov	2026	0	t	f
3450	491	Jun	2026	0	t	f
3451	491	Jul	2026	5	t	f
3452	491	Ago	2026	25	t	f
3453	491	Set	2026	100	t	f
3454	491	Out	2026	100	t	f
3455	491	Nov	2026	100	t	f
3456	424	Nov	2026	0	t	f
3457	167	Set	2026	0	t	f
3458	167	Out	2026	0	t	f
3459	167	Nov	2026	0	t	f
3460	492	Jun	2026	100	t	f
3461	492	Jul	2026	100	t	f
3462	492	Ago	2026	100	t	f
3463	492	Set	2026	100	t	f
3464	492	Out	2026	100	t	f
3465	492	Nov	2026	0	t	f
3466	493	Jun	2026	100	t	f
3467	493	Jul	2026	100	t	f
3468	493	Ago	2026	100	t	f
3469	493	Set	2026	100	t	f
3470	493	Out	2026	100	t	f
3471	493	Nov	2026	0	t	f
3472	94	Nov	2026	100	t	f
3473	11	Nov	2026	100	t	f
3474	395	Nov	2026	100	t	f
3475	394	Nov	2026	100	t	f
3476	391	Nov	2026	100	t	f
3477	390	Nov	2026	100	t	f
3478	383	Nov	2026	0	t	f
3479	257	Nov	2026	100	t	f
3480	256	Nov	2026	100	t	f
3481	255	Nov	2026	100	t	f
3482	254	Nov	2026	100	t	f
3483	252	Nov	2026	100	t	f
3484	251	Nov	2026	100	t	f
3485	249	Nov	2026	100	t	f
3486	21	Nov	2026	100	t	f
3487	154	Nov	2026	100	t	f
3488	110	Nov	2026	100	t	f
3489	52	Nov	2026	100	t	f
3490	104	Nov	2026	100	t	f
3491	87	Nov	2026	100	t	f
3492	16	Nov	2026	100	t	f
3493	283	Nov	2026	0	t	f
3494	279	Nov	2026	0	t	f
3495	471	Dez	2026	0	t	f
3496	475	Dez	2026	0	t	f
3497	171	Dez	2026	0	t	f
3498	459	Dez	2026	0	t	f
3499	468	Dez	2026	0	t	f
3500	179	Dez	2026	0	t	f
3501	216	Nov	2026	0	t	f
3502	216	Dez	2026	0	t	f
3503	494	Jul	2026	0	t	f
3504	494	Ago	2026	0	t	f
3505	494	Set	2026	0	t	f
3506	494	Out	2026	100	t	f
3507	494	Nov	2026	100	t	f
3508	494	Dez	2026	0	t	f
3509	182	Dez	2026	0	t	f
3510	495	Jul	2026	0	t	f
3511	495	Ago	2026	25	t	f
3512	495	Set	2026	0	t	f
3513	495	Out	2026	90	t	f
3514	495	Nov	2026	90	t	f
3515	495	Dez	2026	90	t	f
3516	401	Dez	2026	10	t	f
3517	470	Dez	2026	0	t	f
3518	187	Dez	2026	0	t	f
3519	455	Nov	2026	50	t	f
3520	455	Dez	2026	50	t	f
3521	188	Nov	2026	0	t	f
3522	188	Dez	2026	0	t	f
3523	214	Nov	2026	0	t	f
3524	214	Dez	2026	0	t	f
3525	215	Nov	2026	0	t	f
3526	215	Dez	2026	0	t	f
3527	397	Dez	2026	0	t	f
3528	420	Dez	2026	0	t	f
3529	192	Dez	2026	0	t	f
3530	193	Dez	2026	0	t	f
3531	376	Nov	2026	0	t	f
3532	376	Dez	2026	0	t	f
3533	377	Nov	2026	50	t	f
3534	377	Dez	2026	0	t	f
3535	195	Nov	2026	0	t	f
3536	195	Dez	2026	0	t	f
3537	196	Nov	2026	0	t	f
3538	196	Dez	2026	0	t	f
3539	363	Nov	2026	0	t	f
3540	363	Dez	2026	0	t	f
3541	197	Nov	2026	0	t	f
3542	197	Dez	2026	0	t	f
3543	198	Nov	2026	0	t	f
3544	198	Dez	2026	0	t	f
3545	404	Dez	2026	0	t	f
3546	396	Dez	2026	0	t	f
3547	421	Dez	2026	0	t	f
3548	204	Dez	2026	0	t	f
3549	199	Nov	2026	0	t	f
3550	199	Dez	2026	0	t	f
3551	200	Nov	2026	0	t	f
3552	200	Dez	2026	0	t	f
3553	189	Nov	2026	0	t	f
3554	189	Dez	2026	0	t	f
3555	211	Nov	2026	0	t	f
3556	211	Dez	2026	0	t	f
3557	416	Dez	2026	0	t	f
3558	398	Dez	2026	20	t	f
3559	418	Dez	2026	20	t	f
3560	183	Dez	2026	0	t	f
3561	399	Dez	2026	0	t	f
3562	417	Dez	2026	0	t	f
3563	170	Dez	2026	10	t	f
3564	186	Dez	2026	0	t	f
3565	491	Dez	2026	100	t	f
3566	203	Dez	2026	0	t	f
3567	209	Dez	2026	0	t	f
3568	381	Dez	2026	0	t	f
3569	361	Dez	2026	0	t	f
3570	496	Jul	2026	0	t	f
3571	496	Ago	2026	100	t	f
3572	496	Set	2026	100	t	f
3573	496	Out	2026	0	t	f
3574	496	Nov	2026	0	t	f
3575	496	Dez	2026	0	t	f
3576	230	Set	2026	0	t	f
3577	230	Out	2026	0	t	f
3578	230	Nov	2026	0	t	f
3579	230	Dez	2026	0	t	f
3580	497	Jul	2026	100	t	f
3581	497	Ago	2026	100	t	f
3582	497	Set	2026	0	t	f
3583	497	Out	2026	0	t	f
3584	497	Nov	2026	100	t	f
3585	497	Dez	2026	0	t	f
3586	453	Nov	2026	0	t	f
3587	453	Dez	2026	0	t	f
3588	454	Nov	2026	10	t	f
3589	454	Dez	2026	0	t	f
3590	498	Jul	2026	50	t	f
3591	498	Ago	2026	90	t	f
3592	498	Set	2026	0	t	f
3593	498	Out	2026	0	t	f
3594	498	Nov	2026	90	t	f
3595	498	Dez	2026	0	t	f
3596	499	Jul	2026	50	t	f
3597	499	Ago	2026	40	t	f
3598	499	Set	2026	30	t	f
3599	499	Out	2026	30	t	f
3600	499	Nov	2026	10	t	f
3601	499	Dez	2026	0	t	f
3602	500	Jul	2026	50	t	f
3603	500	Ago	2026	40	t	f
3604	500	Set	2026	10	t	f
3605	500	Out	2026	0	t	f
3606	500	Nov	2026	0	t	f
3607	500	Dez	2026	0	t	f
3608	501	Jul	2026	0	t	f
3609	501	Ago	2026	20	t	f
3610	501	Set	2026	0	t	f
3611	501	Out	2026	0	t	f
3612	501	Nov	2026	0	t	f
3613	501	Dez	2026	0	t	f
3614	175	Nov	2026	10	t	f
3615	175	Dez	2026	0	t	f
3616	439	Nov	2026	10	t	f
3617	439	Dez	2026	0	t	f
3618	441	Nov	2026	70	t	f
3619	441	Dez	2026	0	t	f
3620	440	Nov	2026	10	t	f
3621	440	Dez	2026	0	t	f
3622	447	Nov	2026	0	t	f
3623	447	Dez	2026	0	t	f
3624	502	Jul	2026	0	t	f
3625	502	Ago	2026	10	t	f
3626	502	Set	2026	10	t	f
3627	502	Out	2026	10	t	f
3628	502	Nov	2026	0	t	f
3629	502	Dez	2026	0	t	f
3630	442	Nov	2026	0	t	f
3631	442	Dez	2026	0	t	f
3632	445	Nov	2026	0	t	f
3633	445	Dez	2026	0	t	f
3634	443	Nov	2026	0	t	f
3635	443	Dez	2026	0	t	f
3636	444	Nov	2026	0	t	f
3637	444	Dez	2026	0	t	f
3638	503	Jul	2026	40	t	f
3639	503	Ago	2026	0	t	f
3640	503	Set	2026	0	t	f
3641	503	Out	2026	0	t	f
3642	503	Nov	2026	0	t	f
3643	503	Dez	2026	0	t	f
3644	504	Jul	2026	10	t	f
3645	504	Ago	2026	100	t	f
3646	504	Set	2026	100	t	f
3647	504	Out	2026	100	t	f
3648	504	Nov	2026	50	t	f
3649	504	Dez	2026	0	t	f
3650	505	Jul	2026	0	t	f
3651	505	Ago	2026	0	t	f
3652	505	Set	2026	0	t	f
3653	505	Out	2026	0	t	f
3654	505	Nov	2026	0	t	f
3655	505	Dez	2026	0	t	f
3656	506	Jul	2026	50	t	f
3657	506	Ago	2026	0	t	f
3658	506	Set	2026	0	t	f
3659	506	Out	2026	0	t	f
3660	506	Nov	2026	50	t	f
3661	506	Dez	2026	0	t	f
3662	220	Set	2026	0	t	f
3663	220	Out	2026	0	t	f
3664	220	Nov	2026	0	t	f
3665	220	Dez	2026	0	t	f
3666	507	Jul	2026	10	t	f
3667	507	Ago	2026	10	t	f
3668	507	Set	2026	0	t	f
3669	507	Out	2026	0	t	f
3670	507	Nov	2026	0	t	f
3671	507	Dez	2026	0	t	f
3672	508	Jul	2026	0	t	f
3673	508	Ago	2026	0	t	f
3674	508	Set	2026	0	t	f
3675	508	Out	2026	0	t	f
3676	508	Nov	2026	0	t	f
3677	508	Dez	2026	0	t	f
3678	509	Jul	2026	90	t	f
3679	509	Ago	2026	90	t	f
3680	509	Set	2026	40	t	f
3681	509	Out	2026	20	t	f
3682	509	Nov	2026	0	t	f
3683	509	Dez	2026	0	t	f
3684	510	Jul	2026	0	t	f
3685	510	Ago	2026	20	t	f
3686	510	Set	2026	20	t	f
3687	510	Out	2026	20	t	f
3688	510	Nov	2026	10	t	f
3689	510	Dez	2026	0	t	f
3690	511	Jul	2026	100	t	f
3691	511	Ago	2026	20	t	f
3692	511	Set	2026	20	t	f
3693	511	Out	2026	20	t	f
3694	511	Nov	2026	10	t	f
3695	511	Dez	2026	0	t	f
3696	512	Jul	2026	0	t	f
3697	512	Ago	2026	20	t	f
3698	512	Set	2026	20	t	f
3699	512	Out	2026	20	t	f
3700	512	Nov	2026	10	t	f
3701	512	Dez	2026	0	t	f
3702	513	Jul	2026	50	t	f
3703	513	Ago	2026	90	t	f
3704	513	Set	2026	90	t	f
3705	513	Out	2026	10	t	f
3706	513	Nov	2026	80	t	f
3707	513	Dez	2026	0	t	f
3708	514	Jul	2026	50	t	f
3709	514	Ago	2026	10	t	f
3710	514	Set	2026	10	t	f
3711	514	Out	2026	10	t	f
3712	514	Nov	2026	10	t	f
3713	514	Dez	2026	0	t	f
3714	448	Nov	2026	0	t	f
3715	448	Dez	2026	0	t	f
3716	449	Nov	2026	0	t	f
3717	449	Dez	2026	0	t	f
3718	450	Nov	2026	0	t	f
3719	450	Dez	2026	0	t	f
3720	451	Nov	2026	100	t	f
3721	451	Dez	2026	0	t	f
3722	452	Nov	2026	0	t	f
3723	452	Dez	2026	0	t	f
3724	60	Set	2026	0	t	f
3725	60	Out	2026	0	t	f
3726	60	Nov	2026	0	t	f
3727	60	Dez	2026	0	t	f
3728	515	Jul	2026	0	t	f
3729	515	Ago	2026	80	t	f
3730	515	Set	2026	20	t	f
3731	515	Out	2026	20	t	f
3732	515	Nov	2026	20	t	f
3733	515	Dez	2026	0	t	f
3734	516	Jul	2026	10	t	f
3735	516	Ago	2026	0	t	f
3736	516	Set	2026	10	t	f
3737	516	Out	2026	10	t	f
3738	516	Nov	2026	10	t	f
3739	516	Dez	2026	0	t	f
3740	517	Jul	2026	60	t	f
3741	517	Ago	2026	10	t	f
3742	517	Set	2026	0	t	f
3743	517	Out	2026	0	t	f
3744	517	Nov	2026	0	t	f
3745	517	Dez	2026	0	t	f
3746	518	Jul	2026	30	t	f
3747	518	Ago	2026	10	t	f
3748	518	Set	2026	0	t	f
3749	518	Out	2026	0	t	f
3750	518	Nov	2026	0	t	f
3751	518	Dez	2026	0	t	f
3752	519	Jul	2026	25	t	f
3753	519	Ago	2026	10	t	f
3754	519	Set	2026	20	t	f
3755	519	Out	2026	10	t	f
3756	519	Nov	2026	10	t	f
3757	519	Dez	2026	0	t	f
3758	210	Dez	2026	20	t	f
3759	520	Jul	2026	100	t	f
3760	520	Ago	2026	50	t	f
3761	520	Set	2026	30	t	f
3762	520	Out	2026	30	t	f
3763	520	Nov	2026	30	t	f
3764	520	Dez	2026	20	t	f
3765	521	Jul	2026	100	t	f
3766	521	Ago	2026	100	t	f
3767	521	Set	2026	0	t	f
3768	521	Out	2026	0	t	f
3769	521	Nov	2026	0	t	f
3770	521	Dez	2026	0	t	f
3771	202	Dez	2026	0	t	f
3772	207	Nov	2026	0	t	f
3773	207	Dez	2026	0	t	f
3774	388	Nov	2026	0	t	f
3775	388	Dez	2026	0	t	f
3776	522	Jul	2026	50	t	f
3777	522	Ago	2026	0	t	f
3778	522	Set	2026	0	t	f
3779	522	Out	2026	0	t	f
3780	522	Nov	2026	0	t	f
3781	522	Dez	2026	0	t	f
3782	23	Nov	2026	0	t	f
3783	23	Dez	2026	0	t	f
3784	523	Jul	2026	0	t	f
3785	523	Ago	2026	100	t	f
3786	523	Set	2026	100	t	f
3787	523	Out	2026	100	t	f
3788	523	Nov	2026	0	t	f
3789	523	Dez	2026	0	t	f
3790	524	Jul	2026	0	t	f
3791	524	Ago	2026	100	t	f
3792	524	Set	2026	0	t	f
3793	524	Out	2026	0	t	f
3794	524	Nov	2026	0	t	f
3795	524	Dez	2026	0	t	f
3796	525	Jul	2026	0	t	f
3797	525	Ago	2026	0	t	f
3798	525	Set	2026	20	t	f
3799	525	Out	2026	10	t	f
3800	525	Nov	2026	0	t	f
3801	525	Dez	2026	0	t	f
3802	400	Dez	2026	25	t	f
3803	469	Dez	2026	0	t	f
3804	180	Dez	2026	0	t	f
3805	490	Dez	2026	100	t	f
3806	402	Dez	2026	0	t	f
3807	194	Dez	2026	0	t	f
3808	526	Jul	2026	0	t	f
3809	526	Ago	2026	0	t	f
3810	526	Set	2026	50	t	f
3811	526	Out	2026	0	t	f
3812	526	Nov	2026	0	t	f
3813	526	Dez	2026	0	t	f
3814	473	Dez	2026	50	t	f
3815	422	Dez	2026	0	t	f
3816	403	Dez	2026	0	t	f
3817	208	Dez	2026	0	t	f
3818	527	Jul	2026	0	t	f
3819	527	Ago	2026	0	t	f
3820	527	Set	2026	25	t	f
3821	527	Out	2026	25	t	f
3822	527	Nov	2026	25	t	f
3823	527	Dez	2026	25	t	f
3824	463	Dez	2026	0	t	f
3825	113	Dez	2026	0	t	f
3826	528	Jul	2026	0	t	f
3827	528	Ago	2026	0	t	f
3828	528	Set	2026	75	t	f
3829	528	Out	2026	80	t	f
3830	528	Nov	2026	80	t	f
3831	528	Dez	2026	100	t	f
3832	472	Dez	2026	100	t	f
3833	181	Dez	2026	0	t	f
3834	529	Jul	2026	0	t	f
3835	529	Ago	2026	0	t	f
3836	529	Set	2026	100	t	f
3837	529	Out	2026	100	t	f
3838	529	Nov	2026	100	t	f
3839	529	Dez	2026	50	t	f
3840	275	Dez	2026	0	t	f
3841	434	Dez	2026	0	t	f
3842	274	Nov	2026	0	t	f
3843	274	Dez	2026	0	t	f
3844	530	Jul	2026	10	t	f
3845	530	Ago	2026	60	t	f
3846	530	Set	2026	20	t	f
3847	530	Out	2026	5	t	f
3848	530	Nov	2026	0	t	f
3849	530	Dez	2026	5	t	f
3850	279	Dez	2026	5	t	f
3851	531	Jul	2026	10	t	f
3852	531	Ago	2026	5	t	f
3853	531	Set	2026	20	t	f
3854	531	Out	2026	5	t	f
3855	531	Nov	2026	0	t	f
3856	531	Dez	2026	5	t	f
3857	532	Jul	2026	10	t	f
3858	532	Ago	2026	30	t	f
3859	532	Set	2026	35	t	f
3860	532	Out	2026	80	t	f
3861	532	Nov	2026	100	t	f
3862	532	Dez	2026	85	t	f
3863	533	Jul	2026	55	t	f
3864	533	Ago	2026	55	t	f
3865	533	Set	2026	60	t	f
3866	533	Out	2026	60	t	f
3867	533	Nov	2026	5	t	f
3868	533	Dez	2026	10	t	f
3869	281	Dez	2026	0	t	f
3870	534	Jul	2026	25	t	f
3871	534	Ago	2026	40	t	f
3872	534	Set	2026	5	t	f
3873	534	Out	2026	10	t	f
3874	534	Nov	2026	5	t	f
3875	534	Dez	2026	0	t	f
3876	535	Jul	2026	15	t	f
3877	535	Ago	2026	5	t	f
3878	535	Set	2026	35	t	f
3879	535	Out	2026	30	t	f
3880	535	Nov	2026	5	t	f
3881	535	Dez	2026	0	t	f
3882	536	Jul	2026	30	t	f
3883	536	Ago	2026	30	t	f
3884	536	Set	2026	20	t	f
3885	536	Out	2026	0	t	f
3886	536	Nov	2026	0	t	f
3887	536	Dez	2026	0	t	f
3888	269	Nov	2026	0	t	f
3889	269	Dez	2026	0	t	f
3890	537	Jul	2026	0	t	f
3891	537	Ago	2026	70	t	f
3892	537	Set	2026	60	t	f
3893	537	Out	2026	30	t	f
3894	537	Nov	2026	40	t	f
3895	537	Dez	2026	0	t	f
3896	538	Jul	2026	50	t	f
3897	538	Ago	2026	0	t	f
3898	538	Set	2026	0	t	f
3899	538	Out	2026	0	t	f
3900	538	Nov	2026	0	t	f
3901	538	Dez	2026	0	t	f
3902	539	Jul	2026	60	t	f
3903	539	Ago	2026	60	t	f
3904	539	Set	2026	100	t	f
3905	539	Out	2026	0	t	f
3906	539	Nov	2026	0	t	f
3907	539	Dez	2026	0	t	f
3908	283	Dez	2026	0	t	f
3909	540	Jul	2026	30	t	f
3910	540	Ago	2026	40	t	f
3911	540	Set	2026	0	t	f
3912	540	Out	2026	0	t	f
3913	540	Nov	2026	0	t	f
3914	540	Dez	2026	0	t	f
3915	541	Jul	2026	10	t	f
3916	541	Ago	2026	15	t	f
3917	541	Set	2026	0	t	f
3918	541	Out	2026	0	t	f
3919	541	Nov	2026	0	t	f
3920	541	Dez	2026	0	t	f
3921	542	Jul	2026	20	t	f
3922	542	Ago	2026	40	t	f
3923	542	Set	2026	40	t	f
3924	542	Out	2026	30	t	f
3925	542	Nov	2026	20	t	f
3926	542	Dez	2026	0	t	f
3927	280	Nov	2026	0	t	f
3928	280	Dez	2026	0	t	f
3929	543	Jul	2026	30	t	f
3930	543	Ago	2026	30	t	f
3931	543	Set	2026	55	t	f
3932	543	Out	2026	70	t	f
3933	543	Nov	2026	80	t	f
3934	543	Dez	2026	0	t	f
3935	544	Jul	2026	20	t	f
3936	544	Ago	2026	5	t	f
3937	544	Set	2026	0	t	f
3938	544	Out	2026	0	t	f
3939	544	Nov	2026	0	t	f
3940	544	Dez	2026	0	t	f
3941	545	Jul	2026	5	t	f
3942	545	Ago	2026	5	t	f
3943	545	Set	2026	0	t	f
3944	545	Out	2026	0	t	f
3945	545	Nov	2026	0	t	f
3946	545	Dez	2026	0	t	f
3947	546	Jul	2026	10	t	f
3948	546	Ago	2026	5	t	f
3949	546	Set	2026	5	t	f
3950	546	Out	2026	0	t	f
3951	546	Nov	2026	0	t	f
3952	546	Dez	2026	0	t	f
3953	547	Jul	2026	80	t	f
3954	547	Ago	2026	90	t	f
3955	547	Set	2026	0	t	f
3956	547	Out	2026	0	t	f
3957	547	Nov	2026	0	t	f
3958	547	Dez	2026	0	t	f
3959	143	Nov	2026	0	t	f
3960	143	Dez	2026	0	t	f
3961	548	Jul	2026	15	t	f
3962	548	Ago	2026	10	t	f
3963	548	Set	2026	0	t	f
3964	548	Out	2026	0	t	f
3965	548	Nov	2026	0	t	f
3966	548	Dez	2026	0	t	f
3967	549	Jul	2026	20	t	f
3968	549	Ago	2026	70	t	f
3969	549	Set	2026	90	t	f
3970	549	Out	2026	0	t	f
3971	549	Nov	2026	0	t	f
3972	549	Dez	2026	0	t	f
3973	276	Nov	2026	0	t	f
3974	276	Dez	2026	0	t	f
3975	550	Jul	2026	30	t	f
3976	550	Ago	2026	10	t	f
3977	550	Set	2026	5	t	f
3978	550	Out	2026	0	t	f
3979	550	Nov	2026	0	t	f
3980	550	Dez	2026	0	t	f
3981	551	Jul	2026	45	t	f
3982	551	Ago	2026	20	t	f
3983	551	Set	2026	5	t	f
3984	551	Out	2026	0	t	f
3985	551	Nov	2026	0	t	f
3986	551	Dez	2026	0	t	f
3987	552	Jul	2026	35	t	f
3988	552	Ago	2026	55	t	f
3989	552	Set	2026	75	t	f
3990	552	Out	2026	0	t	f
3991	552	Nov	2026	0	t	f
3992	552	Dez	2026	0	t	f
3993	282	Dez	2026	0	t	f
3994	553	Jul	2026	10	t	f
3995	553	Ago	2026	0	t	f
3996	553	Set	2026	0	t	f
3997	553	Out	2026	0	t	f
3998	553	Nov	2026	0	t	f
3999	553	Dez	2026	0	t	f
4000	554	Jul	2026	50	t	f
4001	554	Ago	2026	45	t	f
4002	554	Set	2026	25	t	f
4003	554	Out	2026	0	t	f
4004	554	Nov	2026	0	t	f
4005	554	Dez	2026	0	t	f
4006	277	Nov	2026	0	t	f
4007	277	Dez	2026	0	t	f
4008	555	Jul	2026	10	t	f
4009	555	Ago	2026	20	t	f
4010	555	Set	2026	10	t	f
4011	555	Out	2026	5	t	f
4012	555	Nov	2026	0	t	f
4013	555	Dez	2026	0	t	f
4014	556	Jul	2026	50	t	f
4015	556	Ago	2026	60	t	f
4016	556	Set	2026	20	t	f
4017	556	Out	2026	5	t	f
4018	556	Nov	2026	0	t	f
4019	556	Dez	2026	0	t	f
4020	486	Dez	2026	0	t	f
4021	488	Dez	2026	0	t	f
4022	557	Jul	2026	100	t	f
4023	557	Ago	2026	100	t	f
4024	557	Set	2026	100	t	f
4025	557	Out	2026	0	t	f
4026	557	Nov	2026	0	t	f
4027	557	Dez	2026	0	t	f
4028	558	Jul	2026	100	t	f
4029	558	Ago	2026	100	t	f
4030	558	Set	2026	100	t	f
4031	558	Out	2026	0	t	f
4032	558	Nov	2026	0	t	f
4033	558	Dez	2026	0	t	f
4034	559	Jul	2026	100	t	f
4035	559	Ago	2026	100	t	f
4036	559	Set	2026	100	t	f
4037	559	Out	2026	0	t	f
4038	559	Nov	2026	0	t	f
4039	559	Dez	2026	0	t	f
4040	560	Jul	2026	100	t	f
4041	560	Ago	2026	100	t	f
4042	560	Set	2026	100	t	f
4043	560	Out	2026	0	t	f
4044	560	Nov	2026	0	t	f
4045	560	Dez	2026	0	t	f
4046	561	Jul	2026	100	t	f
4047	561	Ago	2026	100	t	f
4048	561	Set	2026	100	t	f
4049	561	Out	2026	0	t	f
4050	561	Nov	2026	0	t	f
4051	561	Dez	2026	0	t	f
4052	562	Jul	2026	100	t	f
4053	562	Ago	2026	100	t	f
4054	562	Set	2026	100	t	f
4055	562	Out	2026	0	t	f
4056	562	Nov	2026	0	t	f
4057	562	Dez	2026	0	t	f
4058	563	Jul	2026	100	t	f
4059	563	Ago	2026	100	t	f
4060	563	Set	2026	100	t	f
4061	563	Out	2026	0	t	f
4062	563	Nov	2026	0	t	f
4063	563	Dez	2026	0	t	f
4064	564	Jul	2026	100	t	f
4065	564	Ago	2026	100	t	f
4066	564	Set	2026	100	t	f
4067	564	Out	2026	0	t	f
4068	564	Nov	2026	0	t	f
4069	564	Dez	2026	0	t	f
4070	565	Jul	2026	100	t	f
4071	565	Ago	2026	100	t	f
4072	565	Set	2026	100	t	f
4073	565	Out	2026	0	t	f
4074	565	Nov	2026	0	t	f
4075	565	Dez	2026	0	t	f
4076	566	Jul	2026	100	t	f
4077	566	Ago	2026	40	t	f
4078	566	Set	2026	20	t	f
4079	566	Out	2026	20	t	f
4080	566	Nov	2026	50	t	f
4081	566	Dez	2026	0	t	f
4082	567	Jul	2026	100	t	f
4083	567	Ago	2026	100	t	f
4084	567	Set	2026	100	t	f
4085	567	Out	2026	0	t	f
4086	567	Nov	2026	0	t	f
4087	567	Dez	2026	0	t	f
4088	568	Jul	2026	100	t	f
4089	568	Ago	2026	100	t	f
4090	568	Set	2026	100	t	f
4091	568	Out	2026	0	t	f
4092	568	Nov	2026	0	t	f
4093	568	Dez	2026	0	t	f
4094	569	Jul	2026	100	t	f
4095	569	Ago	2026	100	t	f
4096	569	Set	2026	100	t	f
4097	569	Out	2026	0	t	f
4098	569	Nov	2026	0	t	f
4099	569	Dez	2026	0	t	f
4100	570	Jul	2026	100	t	f
4101	570	Ago	2026	100	t	f
4102	570	Set	2026	100	t	f
4103	570	Out	2026	0	t	f
4104	570	Nov	2026	0	t	f
4105	570	Dez	2026	0	t	f
4106	571	Jul	2026	100	t	f
4107	571	Ago	2026	100	t	f
4108	571	Set	2026	100	t	f
4109	571	Out	2026	0	t	f
4110	571	Nov	2026	0	t	f
4111	571	Dez	2026	0	t	f
4112	572	Jul	2026	100	t	f
4113	572	Ago	2026	100	t	f
4114	572	Set	2026	100	t	f
4115	572	Out	2026	0	t	f
4116	572	Nov	2026	0	t	f
4117	572	Dez	2026	0	t	f
4118	573	Jul	2026	100	t	f
4119	573	Ago	2026	100	t	f
4120	573	Set	2026	100	t	f
4121	573	Out	2026	0	t	f
4122	573	Nov	2026	0	t	f
4123	573	Dez	2026	0	t	f
4124	574	Jul	2026	100	t	f
4125	574	Ago	2026	100	t	f
4126	574	Set	2026	100	t	f
4127	574	Out	2026	0	t	f
4128	574	Nov	2026	0	t	f
4129	574	Dez	2026	0	t	f
4130	575	Jul	2026	100	t	f
4131	575	Ago	2026	100	t	f
4132	575	Set	2026	100	t	f
4133	575	Out	2026	0	t	f
4134	575	Nov	2026	0	t	f
4135	575	Dez	2026	0	t	f
4136	576	Jul	2026	100	t	f
4137	576	Ago	2026	100	t	f
4138	576	Set	2026	100	t	f
4139	576	Out	2026	0	t	f
4140	576	Nov	2026	0	t	f
4141	576	Dez	2026	0	t	f
4142	577	Jul	2026	100	t	f
4143	577	Ago	2026	100	t	f
4144	577	Set	2026	100	t	f
4145	577	Out	2026	0	t	f
4146	577	Nov	2026	0	t	f
4147	577	Dez	2026	0	t	f
4148	578	Jul	2026	100	t	f
4149	578	Ago	2026	100	t	f
4150	578	Set	2026	100	t	f
4151	578	Out	2026	0	t	f
4152	578	Nov	2026	0	t	f
4153	578	Dez	2026	0	t	f
4154	579	Jul	2026	100	t	f
4155	579	Ago	2026	100	t	f
4156	579	Set	2026	100	t	f
4157	579	Out	2026	0	t	f
4158	579	Nov	2026	0	t	f
4159	579	Dez	2026	0	t	f
4160	458	Nov	2026	100	t	f
4161	458	Dez	2026	100	t	f
4162	457	Nov	2026	100	t	f
4163	457	Dez	2026	100	t	f
4164	358	Set	2026	100	t	f
4165	358	Out	2026	100	t	f
4166	358	Nov	2026	100	t	f
4167	358	Dez	2026	100	t	f
4168	357	Set	2026	100	t	f
4169	357	Out	2026	100	t	f
4170	357	Nov	2026	100	t	f
4171	357	Dez	2026	100	t	f
4172	356	Set	2026	100	t	f
4173	356	Out	2026	100	t	f
4174	356	Nov	2026	100	t	f
4175	356	Dez	2026	100	t	f
4176	355	Set	2026	100	t	f
4177	355	Out	2026	100	t	f
4178	355	Nov	2026	100	t	f
4179	355	Dez	2026	100	t	f
4204	353	Set	2026	100	t	f
4205	353	Out	2026	100	t	f
4206	353	Nov	2026	100	t	f
4207	353	Dez	2026	100	t	f
4208	352	Set	2026	100	t	f
4209	352	Out	2026	100	t	f
4210	352	Nov	2026	100	t	f
4211	352	Dez	2026	100	t	f
4212	351	Set	2026	100	t	f
4213	351	Out	2026	100	t	f
4214	351	Nov	2026	100	t	f
4215	351	Dez	2026	100	t	f
4216	350	Set	2026	100	t	f
4217	350	Out	2026	100	t	f
4218	350	Nov	2026	100	t	f
4219	350	Dez	2026	100	t	f
4220	349	Set	2026	100	t	f
4221	349	Out	2026	100	t	f
4222	349	Nov	2026	100	t	f
4223	349	Dez	2026	100	t	f
4224	348	Set	2026	100	t	f
4225	348	Out	2026	100	t	f
4226	348	Nov	2026	100	t	f
4227	348	Dez	2026	100	t	f
4228	347	Set	2026	100	t	f
4229	347	Out	2026	100	t	f
4230	347	Nov	2026	100	t	f
4231	347	Dez	2026	100	t	f
4232	346	Set	2026	100	t	f
4233	346	Out	2026	100	t	f
4234	346	Nov	2026	0	t	f
4235	346	Dez	2026	0	t	f
4236	344	Set	2026	100	t	f
4237	344	Out	2026	100	t	f
4238	344	Nov	2026	100	t	f
4239	344	Dez	2026	100	t	f
4240	343	Set	2026	100	t	f
4241	343	Out	2026	100	t	f
4242	343	Nov	2026	100	t	f
4243	343	Dez	2026	100	t	f
4244	342	Set	2026	100	t	f
4245	342	Out	2026	100	t	f
4246	342	Nov	2026	100	t	f
4247	342	Dez	2026	100	t	f
4248	341	Set	2026	100	t	f
4249	341	Out	2026	100	t	f
4250	341	Nov	2026	100	t	f
4251	341	Dez	2026	100	t	f
4252	340	Set	2026	100	t	f
4253	340	Out	2026	100	t	f
4254	340	Nov	2026	100	t	f
4255	340	Dez	2026	100	t	f
4256	339	Set	2026	100	t	f
4257	339	Out	2026	100	t	f
4258	339	Nov	2026	100	t	f
4259	339	Dez	2026	100	t	f
4260	338	Set	2026	100	t	f
4261	338	Out	2026	100	t	f
4262	338	Nov	2026	100	t	f
4263	338	Dez	2026	100	t	f
4264	337	Set	2026	100	t	f
4265	337	Out	2026	100	t	f
4266	337	Nov	2026	100	t	f
4267	337	Dez	2026	100	t	f
4268	336	Set	2026	100	t	f
4269	336	Out	2026	100	t	f
4270	336	Nov	2026	100	t	f
4271	336	Dez	2026	100	t	f
4272	335	Set	2026	100	t	f
4273	335	Out	2026	100	t	f
4274	335	Nov	2026	100	t	f
4275	335	Dez	2026	100	t	f
4276	334	Set	2026	100	t	f
4277	334	Out	2026	100	t	f
4278	334	Nov	2026	100	t	f
4279	334	Dez	2026	100	t	f
4280	333	Set	2026	100	t	f
4281	333	Out	2026	100	t	f
4282	333	Nov	2026	100	t	f
4283	333	Dez	2026	100	t	f
4284	332	Set	2026	100	t	f
4285	332	Out	2026	100	t	f
4286	332	Nov	2026	100	t	f
4287	332	Dez	2026	100	t	f
4288	331	Set	2026	100	t	f
4289	331	Out	2026	100	t	f
4290	331	Nov	2026	100	t	f
4291	331	Dez	2026	100	t	f
4300	480	Dez	2026	0	t	f
4301	480	Jan	2027	0	t	f
4302	393	Nov	2026	0	t	f
4303	393	Dez	2026	0	t	f
4304	393	Jan	2027	0	t	f
4305	87	Dez	2026	0	t	f
4306	87	Jan	2027	0	t	f
4307	394	Dez	2026	0	t	f
4308	394	Jan	2027	0	t	f
4309	110	Dez	2026	0	t	f
4310	110	Jan	2027	0	t	f
4311	104	Dez	2026	0	t	f
4312	104	Jan	2027	0	t	f
4313	11	Dez	2026	0	t	f
4314	11	Jan	2027	0	t	f
4315	94	Dez	2026	0	t	f
4316	94	Jan	2027	0	t	f
4317	52	Dez	2026	0	t	f
4318	52	Jan	2027	0	t	f
4319	395	Dez	2026	0	t	f
4320	395	Jan	2027	0	t	f
4321	249	Dez	2026	0	t	f
4322	249	Jan	2027	0	t	f
4323	154	Dez	2026	0	t	f
4324	154	Jan	2027	0	t	f
4325	431	Nov	2026	0	t	f
4326	431	Dez	2026	0	t	f
4327	431	Jan	2027	0	t	f
4328	16	Dez	2026	0	t	f
4329	16	Jan	2027	0	t	f
4330	390	Dez	2026	0	t	f
4331	390	Jan	2027	0	t	f
4332	391	Dez	2026	0	t	f
4333	391	Jan	2027	0	t	f
4334	487	Dez	2026	0	t	f
4335	487	Jan	2027	0	t	f
4336	251	Dez	2026	0	t	f
4337	251	Jan	2027	0	t	f
4338	252	Dez	2026	0	t	f
4339	252	Jan	2027	0	t	f
4340	383	Dez	2026	0	t	f
4341	383	Jan	2027	0	t	f
4342	254	Dez	2026	0	t	f
4343	254	Jan	2027	0	t	f
4344	255	Dez	2026	0	t	f
4345	255	Jan	2027	0	t	f
4346	256	Dez	2026	0	t	f
4347	256	Jan	2027	0	t	f
4348	387	Nov	2026	0	t	f
4349	387	Dez	2026	0	t	f
4350	387	Jan	2027	0	t	f
4351	257	Dez	2026	0	t	f
4352	257	Jan	2027	0	t	f
4353	385	Nov	2026	0	t	f
4354	385	Dez	2026	0	t	f
4355	385	Jan	2027	0	t	f
4356	389	Nov	2026	0	t	f
4357	389	Dez	2026	0	t	f
4358	389	Jan	2027	0	t	f
4359	400	Jan	2027	0	t	f
4360	469	Jan	2027	0	t	f
4361	180	Jan	2027	0	t	f
4362	580	Ago	2026	0	t	f
4363	580	Set	2026	100	t	f
4364	580	Out	2026	0	t	f
4365	580	Nov	2026	0	t	f
4366	580	Dez	2026	0	t	f
4367	580	Jan	2027	0	t	f
4368	581	Ago	2026	5	t	f
4369	581	Set	2026	0	t	f
4370	581	Out	2026	0	t	f
4371	581	Nov	2026	0	t	f
4372	581	Dez	2026	0	t	f
4373	581	Jan	2027	0	t	f
4374	582	Ago	2026	100	t	f
4375	582	Set	2026	100	t	f
4376	582	Out	2026	100	t	f
4377	582	Nov	2026	100	t	f
4378	582	Dez	2026	100	t	f
4379	582	Jan	2027	0	t	f
4380	583	Ago	2026	100	t	f
4381	583	Set	2026	100	t	f
4382	583	Out	2026	100	t	f
4383	583	Nov	2026	100	t	f
4384	583	Dez	2026	100	t	f
4385	583	Jan	2027	0	t	f
4386	379	Set	2026	100	t	f
4387	379	Out	2026	0	t	f
4388	379	Nov	2026	0	t	f
4389	379	Dez	2026	0	t	f
4390	379	Jan	2027	0	t	f
4391	513	Jan	2027	0	t	f
4392	584	Ago	2026	0	t	f
4393	584	Set	2026	90	t	f
4394	584	Out	2026	80	t	f
4395	584	Nov	2026	10	t	f
4396	584	Dez	2026	0	t	f
4397	584	Jan	2027	0	t	f
4398	514	Jan	2027	0	t	f
4399	214	Jan	2027	0	t	f
4400	525	Jan	2027	0	t	f
4401	524	Jan	2027	0	t	f
4402	215	Jan	2027	0	t	f
4403	585	Ago	2026	0	t	f
4404	585	Set	2026	70	t	f
4405	585	Out	2026	70	t	f
4406	585	Nov	2026	70	t	f
4407	585	Dez	2026	100	t	f
4408	585	Jan	2027	0	t	f
4409	586	Ago	2026	0	t	f
4410	586	Set	2026	10	t	f
4411	586	Out	2026	20	t	f
4412	586	Nov	2026	30	t	f
4413	586	Dez	2026	0	t	f
4414	586	Jan	2027	0	t	f
4415	510	Jan	2027	0	t	f
4416	587	Ago	2026	0	t	f
4417	587	Set	2026	20	t	f
4418	587	Out	2026	20	t	f
4419	587	Nov	2026	20	t	f
4420	587	Dez	2026	0	t	f
4421	587	Jan	2027	0	t	f
4422	511	Jan	2027	0	t	f
4423	512	Jan	2027	0	t	f
4424	566	Jan	2027	0	t	f
4425	220	Jan	2027	0	t	f
4426	507	Jan	2027	0	t	f
4427	508	Jan	2027	0	t	f
4428	588	Ago	2026	0	t	f
4429	588	Set	2026	50	t	f
4430	588	Out	2026	70	t	f
4431	588	Nov	2026	90	t	f
4432	588	Dez	2026	90	t	f
4433	588	Jan	2027	0	t	f
4434	509	Jan	2027	0	t	f
4435	589	Ago	2026	0	t	f
4436	589	Set	2026	10	t	f
4437	589	Out	2026	10	t	f
4438	589	Nov	2026	10	t	f
4439	589	Dez	2026	10	t	f
4440	589	Jan	2027	0	t	f
4441	453	Jan	2027	0	t	f
4442	454	Jan	2027	0	t	f
4443	590	Ago	2026	0	t	f
4444	590	Set	2026	90	t	f
4445	590	Out	2026	90	t	f
4446	590	Nov	2026	0	t	f
4447	590	Dez	2026	0	t	f
4448	590	Jan	2027	0	t	f
4449	498	Jan	2027	0	t	f
4450	175	Jan	2027	0	t	f
4451	439	Jan	2027	0	t	f
4452	591	Ago	2026	0	t	f
4453	591	Set	2026	70	t	f
4454	591	Out	2026	70	t	f
4455	591	Nov	2026	0	t	f
4456	591	Dez	2026	0	t	f
4457	591	Jan	2027	0	t	f
4458	441	Jan	2027	0	t	f
4459	440	Jan	2027	0	t	f
4460	499	Jan	2027	0	t	f
4461	500	Jan	2027	0	t	f
4462	592	Ago	2026	0	t	f
4463	592	Set	2026	60	t	f
4464	592	Out	2026	70	t	f
4465	592	Nov	2026	90	t	f
4466	592	Dez	2026	0	t	f
4467	592	Jan	2027	0	t	f
4468	501	Jan	2027	0	t	f
4469	503	Jan	2027	0	t	f
4470	504	Jan	2027	0	t	f
4471	505	Jan	2027	0	t	f
4472	506	Jan	2027	0	t	f
4473	230	Jan	2027	0	t	f
4474	593	Ago	2026	0	t	f
4475	593	Set	2026	100	t	f
4476	593	Out	2026	100	t	f
4477	593	Nov	2026	0	t	f
4478	593	Dez	2026	0	t	f
4479	593	Jan	2027	0	t	f
4480	497	Jan	2027	0	t	f
4481	594	Ago	2026	0	t	f
4482	594	Set	2026	0	t	f
4483	594	Out	2026	0	t	f
4484	594	Nov	2026	0	t	f
4485	594	Dez	2026	0	t	f
4486	594	Jan	2027	0	t	f
4487	210	Jan	2027	0	t	f
4488	595	Ago	2026	0	t	f
4489	595	Set	2026	40	t	f
4490	595	Out	2026	40	t	f
4491	595	Nov	2026	20	t	f
4492	595	Dez	2026	0	t	f
4493	595	Jan	2027	0	t	f
4494	520	Jan	2027	0	t	f
4495	60	Jan	2027	0	t	f
4496	515	Jan	2027	0	t	f
4497	596	Ago	2026	0	t	f
4498	596	Set	2026	20	t	f
4499	596	Out	2026	20	t	f
4500	596	Nov	2026	20	t	f
4501	596	Dez	2026	0	t	f
4502	596	Jan	2027	0	t	f
4503	597	Ago	2026	0	t	f
4504	597	Set	2026	20	t	f
4505	597	Out	2026	30	t	f
4506	597	Nov	2026	30	t	f
4507	597	Dez	2026	0	t	f
4508	597	Jan	2027	0	t	f
4509	598	Ago	2026	0	t	f
4510	598	Set	2026	30	t	f
4511	598	Out	2026	20	t	f
4512	598	Nov	2026	20	t	f
4513	598	Dez	2026	0	t	f
4514	598	Jan	2027	0	t	f
4515	516	Jan	2027	0	t	f
4516	517	Jan	2027	0	t	f
4517	518	Jan	2027	0	t	f
4518	468	Jan	2027	0	t	f
4519	179	Jan	2027	0	t	f
4520	216	Jan	2027	0	t	f
4521	599	Ago	2026	0	t	f
4522	599	Set	2026	30	t	f
4523	599	Out	2026	65	t	f
4524	599	Nov	2026	75	t	f
4525	599	Dez	2026	75	t	f
4526	599	Jan	2027	0	t	f
4527	472	Jan	2027	0	t	f
4528	181	Jan	2027	0	t	f
4529	494	Jan	2027	0	t	f
4530	182	Jan	2027	0	t	f
4531	416	Jan	2027	0	t	f
4532	398	Jan	2027	0	t	f
4533	418	Jan	2027	0	t	f
4534	183	Jan	2027	0	t	f
4535	399	Jan	2027	0	t	f
4536	417	Jan	2027	0	t	f
4537	495	Jan	2027	0	t	f
4538	401	Jan	2027	0	t	f
4539	470	Jan	2027	0	t	f
4540	187	Jan	2027	0	t	f
4541	455	Jan	2027	0	t	f
4542	188	Jan	2027	0	t	f
4543	376	Jan	2027	0	t	f
4544	377	Jan	2027	0	t	f
4545	195	Jan	2027	0	t	f
4546	196	Jan	2027	0	t	f
4547	363	Jan	2027	0	t	f
4548	197	Jan	2027	0	t	f
4549	198	Jan	2027	0	t	f
4550	199	Jan	2027	0	t	f
4551	200	Jan	2027	0	t	f
4552	189	Jan	2027	0	t	f
4553	473	Jan	2027	50	t	f
4554	422	Jan	2027	0	t	f
4555	403	Jan	2027	0	t	f
4556	208	Jan	2027	0	t	f
4557	529	Jan	2027	0	t	f
4558	209	Jan	2027	0	t	f
4559	211	Jan	2027	0	t	f
4560	474	Dez	2026	0	t	f
4561	474	Jan	2027	0	t	f
4562	370	Dez	2026	0	t	f
4563	370	Jan	2027	0	t	f
4564	446	Dez	2026	0	t	f
4565	446	Jan	2027	0	t	f
4566	170	Jan	2027	0	t	f
4567	519	Jan	2027	0	t	f
4568	186	Jan	2027	0	t	f
4569	600	Ago	2026	0	t	f
4570	600	Set	2026	10	t	f
4571	600	Out	2026	10	t	f
4572	600	Nov	2026	10	t	f
4573	600	Dez	2026	10	t	f
4574	600	Jan	2027	0	t	f
4575	601	Ago	2026	20	t	f
4576	601	Set	2026	20	t	f
4577	601	Out	2026	10	t	f
4578	601	Nov	2026	10	t	f
4579	601	Dez	2026	0	t	f
4580	601	Jan	2027	0	t	f
4581	602	Ago	2026	0	t	f
4582	602	Set	2026	0	t	f
4583	602	Out	2026	25	t	f
4584	602	Nov	2026	25	t	f
4585	602	Dez	2026	25	t	f
4586	602	Jan	2027	25	t	f
4587	603	Ago	2026	100	t	f
4588	603	Set	2026	100	t	f
4589	603	Out	2026	25	t	f
4590	603	Nov	2026	25	t	f
4591	603	Dez	2026	25	t	f
4592	603	Jan	2027	25	t	f
4593	604	Ago	2026	100	t	f
4594	604	Set	2026	100	t	f
4595	604	Out	2026	100	t	f
4596	604	Nov	2026	100	t	f
4597	604	Dez	2026	0	t	f
4598	604	Jan	2027	0	t	f
4599	605	Ago	2026	0	t	f
4600	605	Set	2026	20	t	f
4601	605	Out	2026	50	t	f
4602	605	Nov	2026	50	t	f
4603	605	Dez	2026	0	t	f
4604	605	Jan	2027	0	t	f
4605	606	Ago	2026	0	t	f
4606	606	Set	2026	0	t	f
4607	606	Out	2026	100	t	f
4608	606	Nov	2026	100	t	f
4609	606	Dez	2026	0	t	f
4610	606	Jan	2027	0	t	f
4627	607	Ago	2026	0	t	f
4628	607	Set	2026	100	t	f
4629	607	Out	2026	30	t	f
4630	607	Nov	2026	30	t	f
4631	607	Dez	2026	30	t	f
4632	607	Jan	2027	30	t	f
4633	608	Ago	2026	0	t	f
4634	608	Set	2026	0	t	f
4635	608	Out	2026	70	t	f
4636	608	Nov	2026	70	t	f
4637	608	Dez	2026	70	t	f
4638	608	Jan	2027	70	t	f
4663	381	Jan	2027	0	t	f
4664	496	Jan	2027	0	t	f
4665	205	Dez	2026	0	t	f
4666	205	Jan	2027	0	t	f
4667	206	Dez	2026	0	t	f
4668	206	Jan	2027	0	t	f
4669	405	Dez	2026	0	t	f
4670	405	Jan	2027	0	t	f
4679	471	Jan	2027	0	t	f
4680	475	Jan	2027	0	t	f
4681	609	Ago	2026	0	t	f
4682	609	Set	2026	0	t	f
4683	609	Out	2026	50	t	f
4684	609	Nov	2026	50	t	f
4685	609	Dez	2026	50	t	f
4686	609	Jan	2027	0	t	f
4687	171	Jan	2027	0	t	f
4688	610	Ago	2026	0	t	f
4689	610	Set	2026	0	t	f
4690	610	Out	2026	50	t	f
4691	610	Nov	2026	50	t	f
4692	610	Dez	2026	50	t	f
4693	610	Jan	2027	0	t	f
4694	459	Jan	2027	0	t	f
4698	611	Ago	2026	0	t	f
4699	611	Set	2026	0	t	f
4700	611	Out	2026	25	t	f
4701	611	Nov	2026	25	t	f
4702	611	Dez	2026	25	t	f
4703	611	Jan	2027	25	t	f
4704	612	Ago	2026	0	t	f
4705	612	Set	2026	0	t	f
4706	612	Out	2026	25	t	f
4707	612	Nov	2026	25	t	f
4708	612	Dez	2026	25	t	f
4709	612	Jan	2027	25	t	f
4731	527	Jan	2027	25	t	f
4732	463	Jan	2027	0	t	f
4733	113	Jan	2027	0	t	f
4734	613	Ago	2026	25	t	f
4735	613	Set	2026	25	t	f
4736	613	Out	2026	25	t	f
4737	613	Nov	2026	25	t	f
4738	613	Dez	2026	25	t	f
4739	613	Jan	2027	25	t	f
4740	614	Ago	2026	25	t	f
4741	614	Set	2026	25	t	f
4742	614	Out	2026	25	t	f
4743	614	Nov	2026	25	t	f
4744	614	Dez	2026	25	t	f
4745	614	Jan	2027	25	t	f
4746	549	Jan	2027	0	t	f
4747	276	Jan	2027	0	t	f
4748	615	Ago	2026	0	t	f
4749	615	Set	2026	100	t	f
4750	615	Out	2026	100	t	f
4751	615	Nov	2026	100	t	f
4752	615	Dez	2026	100	t	f
4753	615	Jan	2027	100	t	f
4754	616	Ago	2026	0	t	f
4755	616	Set	2026	0	t	f
4756	616	Out	2026	0	t	f
4757	616	Nov	2026	0	t	f
4758	616	Dez	2026	0	t	f
4759	616	Jan	2027	0	t	f
4760	550	Jan	2027	0	t	f
4761	551	Jan	2027	0	t	f
4762	617	Ago	2026	0	t	f
4763	617	Set	2026	0	t	f
4764	617	Out	2026	50	t	f
4765	617	Nov	2026	50	t	f
4766	617	Dez	2026	50	t	f
4767	617	Jan	2027	50	t	f
4768	539	Jan	2027	0	t	f
4769	283	Jan	2027	0	t	f
4770	618	Ago	2026	0	t	f
4771	618	Set	2026	100	t	f
4772	618	Out	2026	100	t	f
4773	618	Nov	2026	100	t	f
4774	618	Dez	2026	100	t	f
4775	618	Jan	2027	100	t	f
4776	540	Jan	2027	0	t	f
4777	619	Ago	2026	0	t	f
4778	619	Set	2026	0	t	f
4779	619	Out	2026	100	t	f
4780	619	Nov	2026	100	t	f
4781	619	Dez	2026	100	t	f
4782	619	Jan	2027	100	t	f
4783	552	Jan	2027	0	t	f
4784	282	Jan	2027	0	t	f
4785	553	Jan	2027	0	t	f
4786	554	Jan	2027	0	t	f
4787	620	Ago	2026	0	t	f
4788	620	Set	2026	50	t	f
4789	620	Out	2026	50	t	f
4790	620	Nov	2026	50	t	f
4791	620	Dez	2026	50	t	f
4792	620	Jan	2027	50	t	f
4793	621	Ago	2026	0	t	f
4794	621	Set	2026	50	t	f
4795	621	Out	2026	50	t	f
4796	621	Nov	2026	50	t	f
4797	621	Dez	2026	50	t	f
4798	621	Jan	2027	50	t	f
4831	491	Jan	2027	0	t	f
4832	203	Jan	2027	0	t	f
4841	490	Jan	2027	0	t	f
4842	402	Jan	2027	0	t	f
4843	194	Jan	2027	0	t	f
4850	622	Ago	2026	0	t	f
4851	622	Set	2026	0	t	f
4852	622	Out	2026	100	t	f
4853	622	Nov	2026	100	t	f
4854	622	Dez	2026	100	t	f
4855	622	Jan	2027	100	t	f
4856	528	Jan	2027	0	t	f
4857	397	Jan	2027	0	t	f
4858	420	Jan	2027	0	t	f
4859	192	Jan	2027	0	t	f
4860	193	Jan	2027	0	t	f
4877	460	Dez	2026	0	t	f
4878	460	Jan	2027	0	t	f
4879	404	Jan	2027	0	t	f
4880	526	Jan	2027	0	t	f
4881	396	Jan	2027	0	t	f
4882	421	Jan	2027	0	t	f
4883	623	Ago	2026	0	t	f
4884	623	Set	2026	0	t	f
4885	623	Out	2026	50	t	f
4886	623	Nov	2026	50	t	f
4887	623	Dez	2026	50	t	f
4888	623	Jan	2027	50	t	f
4889	204	Jan	2027	0	t	f
4890	345	Set	2026	100	t	f
4891	345	Out	2026	100	t	f
4892	345	Nov	2026	100	t	f
4893	345	Dez	2026	100	t	f
4894	345	Jan	2027	0	t	f
4895	346	Jan	2027	0	t	f
4896	624	Ago	2026	0	t	f
4897	624	Set	2026	0	t	f
4898	624	Out	2026	50	t	f
4899	624	Nov	2026	50	t	f
4900	624	Dez	2026	50	t	f
4901	624	Jan	2027	50	t	f
4902	625	Ago	2026	0	t	f
4903	625	Set	2026	0	t	f
4904	625	Out	2026	100	t	f
4905	625	Nov	2026	100	t	f
4906	625	Dez	2026	100	t	f
4907	625	Jan	2027	100	t	f
4908	364	Dez	2026	100	t	f
4909	364	Jan	2027	0	t	f
4910	354	Nov	2026	50	t	f
4911	354	Dez	2026	50	t	f
4912	354	Jan	2027	50	t	f
4913	247	Nov	2026	50	t	f
4914	247	Dez	2026	50	t	f
4915	247	Jan	2027	50	t	f
4916	361	Jan	2027	0	t	f
4917	361	Fev	2027	0	t	f
4918	527	Fev	2027	0	t	f
4919	463	Fev	2027	0	t	f
4920	113	Fev	2027	0	t	f
4921	613	Fev	2027	0	t	f
4922	614	Fev	2027	0	t	f
4923	626	Set	2026	25	t	f
4924	626	Out	2026	25	t	f
4925	626	Nov	2026	25	t	f
4926	626	Dez	2026	25	t	f
4927	626	Jan	2027	25	t	f
4928	626	Fev	2027	0	t	f
4929	496	Fev	2027	0	t	f
4930	625	Fev	2027	0	t	f
4931	217	Dez	2026	0	t	f
4932	217	Jan	2027	0	t	f
4933	217	Fev	2027	0	t	f
4934	218	Dez	2026	50	t	f
4935	218	Jan	2027	50	t	f
4936	218	Fev	2027	50	t	f
4937	627	Set	2026	0	t	f
4938	627	Out	2026	50	t	f
4939	627	Nov	2026	50	t	f
4940	627	Dez	2026	50	t	f
4941	627	Jan	2027	50	t	f
4942	627	Fev	2027	50	t	f
4943	354	Fev	2027	50	t	f
4944	247	Fev	2027	50	t	f
4945	628	Set	2026	50	t	f
4946	628	Out	2026	50	t	f
4947	628	Nov	2026	50	t	f
4948	628	Dez	2026	50	t	f
4949	628	Jan	2027	50	t	f
4950	628	Fev	2027	50	t	f
4951	629	Set	2026	50	t	f
4952	629	Out	2026	50	t	f
4953	629	Nov	2026	50	t	f
4954	629	Dez	2026	50	t	f
4955	629	Jan	2027	50	t	f
4956	629	Fev	2027	50	t	f
4957	472	Fev	2027	0	t	f
4958	181	Fev	2027	0	t	f
4959	471	Fev	2027	0	t	f
4960	475	Fev	2027	0	t	f
4961	609	Fev	2027	0	t	f
4962	171	Fev	2027	0	t	f
4963	610	Fev	2027	0	t	f
4964	459	Fev	2027	0	t	f
4965	549	Fev	2027	0	t	f
4966	276	Fev	2027	0	t	f
4967	615	Fev	2027	0	t	f
4968	616	Fev	2027	0	t	f
4969	550	Fev	2027	0	t	f
4970	551	Fev	2027	0	t	f
4971	377	Fev	2027	0	t	f
4972	605	Fev	2027	0	t	f
4973	602	Fev	2027	0	t	f
4974	603	Fev	2027	0	t	f
4975	611	Fev	2027	0	t	f
4976	612	Fev	2027	0	t	f
4977	526	Fev	2027	0	t	f
4978	421	Fev	2027	0	t	f
4979	623	Fev	2027	0	t	f
4980	624	Fev	2027	0	t	f
4981	199	Fev	2027	0	t	f
4982	619	Fev	2027	0	t	f
4983	599	Fev	2027	0	t	f
4984	400	Fev	2027	0	t	f
4985	469	Fev	2027	0	t	f
4986	180	Fev	2027	0	t	f
4987	528	Fev	2027	0	t	f
4988	397	Fev	2027	0	t	f
4989	420	Fev	2027	0	t	f
4990	192	Fev	2027	0	t	f
4991	193	Fev	2027	0	t	f
4992	495	Fev	2027	0	t	f
4993	401	Fev	2027	0	t	f
4994	470	Fev	2027	0	t	f
4995	187	Fev	2027	0	t	f
4996	630	Set	2026	0	t	f
4997	630	Out	2026	25	t	f
4998	630	Nov	2026	0	t	f
4999	630	Dez	2026	0	t	f
5000	630	Jan	2027	0	t	f
5001	630	Fev	2027	0	t	f
5002	416	Fev	2027	0	t	f
5003	631	Set	2026	0	t	f
5004	631	Out	2026	9	t	f
5005	631	Nov	2026	0	t	f
5006	631	Dez	2026	0	t	f
5007	631	Jan	2027	0	t	f
5008	631	Fev	2027	0	t	f
5009	398	Fev	2027	0	t	f
5010	418	Fev	2027	0	t	f
5011	632	Set	2026	0	t	f
5012	632	Out	2026	8	t	f
5013	632	Nov	2026	0	t	f
5014	632	Dez	2026	0	t	f
5015	632	Jan	2027	0	t	f
5016	632	Fev	2027	0	t	f
5017	183	Fev	2027	0	t	f
5018	633	Set	2026	0	t	f
5019	633	Out	2026	8	t	f
5020	633	Nov	2026	0	t	f
5021	633	Dez	2026	0	t	f
5022	633	Jan	2027	0	t	f
5023	633	Fev	2027	0	t	f
5024	399	Fev	2027	0	t	f
5025	417	Fev	2027	0	t	f
5026	634	Set	2026	0	t	f
5027	634	Out	2026	0	t	f
5028	634	Nov	2026	60	t	f
5029	634	Dez	2026	60	t	f
5030	634	Jan	2027	0	t	f
5031	634	Fev	2027	0	t	f
5032	455	Fev	2027	0	t	f
5033	188	Fev	2027	0	t	f
5034	635	Set	2026	0	t	f
5035	635	Out	2026	0	t	f
5036	635	Nov	2026	50	t	f
5037	635	Dez	2026	50	t	f
5038	635	Jan	2027	0	t	f
5039	635	Fev	2027	0	t	f
\.


--
-- TOC entry 3629 (class 0 OID 95748)
-- Dependencies: 231
-- Data for Name: skills; Type: TABLE DATA; Schema: InHire; Owner: postgres
--

COPY "InHire".skills (id, nome_skill, id_area_tecnologia, status, deletado) FROM stdin;
1	Arquitetura e Modelagem	168	t	f
2	BPMN	168	t	f
3	BRModelo	168	t	f
4	Clean Architecture	168	t	f
5	Enterprise Architect	168	t	f
6	Erwin	168	t	f
7	Microfrontend	168	t	f
8	Microserviços	168	t	f
9	MVC	168	t	f
10	SQL Modeler	168	t	f
11	StarUML	168	t	f
12	UML	168	t	f
13	CodeIgniter (PHP)	169	t	f
14	Django (Python)	169	t	f
15	Express (Node.js)	169	t	f
16	Java	169	t	f
17	LangChain (Python)	169	t	f
18	Laravel (PHP)	169	t	f
19	Node.js	169	t	f
20	PHP	169	t	f
21	Python	169	t	f
22	PyTorch	169	t	f
23	Quarkus (Java)	169	t	f
24	Rails (Ruby)	169	t	f
25	Ruby	169	t	f
26	Spring Boot (Java)	169	t	f
27	TensorFlow	169	t	f
28	DB2	170	t	f
29	DBeaver	170	t	f
30	Firebase	170	t	f
31	HeidiSQL	170	t	f
32	Informix	170	t	f
33	MariaDB	170	t	f
34	MongoDB	170	t	f
35	MS SQL Server	170	t	f
36	MySQL	170	t	f
37	MySQL Workbench	170	t	f
38	Oracle	170	t	f
39	PL/SQL	170	t	f
40	Postgre	170	t	f
41	PostgreSQL	170	t	f
42	Redis	170	t	f
43	SQLite	170	t	f
44	pgAdmin	170	t	f
45	Airflow	170	t	f
46	Pentaho	170	t	f
47	Balsamiq	171	t	f
48	Bizagi Modeler	171	t	f
49	Draw.io	171	t	f
50	Figma	171	t	f
51	Miro	171	t	f
52	UX/UI	171	t	f
53	Angular	173	t	f
54	AngularJS	173	t	f
55	CSS	173	t	f
56	HTML	173	t	f
57	IONIC	173	t	f
58	JavaScript	173	t	f
59	React	173	t	f
60	React Native	173	t	f
61	TypeScript	173	t	f
62	Vue.js	173	t	f
63	AWS (Amazon Web Services)	174	t	f
64	Azure	174	t	f
65	Docker	174	t	f
66	Docker Compose	174	t	f
67	Docker Swarm	174	t	f
68	EC2 (AWS)	174	t	f
69	GCP (Google Cloud Platform)	174	t	f
70	HAProxy	174	t	f
71	Kubernetes	174	t	f
72	Linux	174	t	f
73	Load Balancer	174	t	f
74	Minio	174	t	f
75	Nginx	174	t	f
76	Portainer	174	t	f
77	Proxmox	174	t	f
78	Rancher	174	t	f
79	RDS (AWS)	174	t	f
80	Traefik	174	t	f
81	Vagrant	174	t	f
82	VirtualBox	174	t	f
83	Appium	175	t	f
84	Cypress	175	t	f
85	Flutter Test	175	t	f
86	Jest	175	t	f
87	JMeter	175	t	f
88	K6	175	t	f
89	Playwright	175	t	f
90	Puppeteer	175	t	f
91	REST Assured	175	t	f
92	Robot Framework	175	t	f
93	Selenide	175	t	f
94	Selenium	175	t	f
95	Signoz	175	t	f
96	TestLink	175	t	f
97	Vitest	175	t	f
98	Azure Boards	176	t	f
99	Bizagi Modeler	176	t	f
100	BPMN	176	t	f
101	Confluence	176	t	f
102	Jira	176	t	f
103	Microsoft Project	176	t	f
104	Miro	176	t	f
105	Planner	176	t	f
106	Trello	176	t	f
107	UML	176	t	f
108	Hash de Senha	177	t	f
109	JWT (JSON Web Token)	177	t	f
110	Keycloak	177	t	f
111	OAuth 2.0	177	t	f
112	Vault	177	t	f
113	Bash	172	t	f
114	CI/CD	172	t	f
115	Git	172	t	f
116	Git Flow	172	t	f
117	GitHub	172	t	f
118	GitHub Actions	172	t	f
119	GitLab	172	t	f
120	GitLab CI	172	t	f
121	HAProxy	172	t	f
122	Jenkins	172	t	f
123	Kubernetes	172	t	f
124	Nginx	172	t	f
125	Rancher	172	t	f
126	Traefik	172	t	f
127	Vault	172	t	f
128	Tailwind	173	t	f
129	Docker	172	t	f
130	WavingTest	175	t	f
131	Rust	169	t	f
132	Pascal	319	t	f
133	C++	169	t	f
134	Delphi	319	t	f
135	C#	169	t	f
136	Kotlin	169	t	f
137	Java EE	169	t	f
138	COBOL	319	t	f
139	SQL	170	t	f
140	C	169	t	f
141	PowerBuilder	319	t	f
142	Visual Basic .NET	169	t	f
143	PL/I	319	t	f
144	Terraform	172	t	f
145	Ansible	172	t	f
146	.NET	169	t	f
147	Swift	169	t	f
148	JCL	319	t	f
149	VSAM	319	t	f
150	ABAP	319	t	f
151	Fortran	319	t	f
152	Go	169	t	f
153	CICS	319	t	f
154	VB6	319	t	f
155	Assembly	319	t	f
156	Data Science	170	t	f
157	PowerBI	170	t	f
158	SAP	169	t	f
159	Flutter	175	t	f
\.


--
-- TOC entry 3641 (class 0 OID 95897)
-- Dependencies: 243
-- Data for Name: talento_skills; Type: TABLE DATA; Schema: InHire; Owner: postgres
--

COPY "InHire".talento_skills (id, id_talento, id_skill, id_nivel_conhecimento) FROM stdin;
1	1	1	320
2	2	8	321
3	3	15	318
4	4	22	320
5	5	29	321
6	6	36	318
7	7	43	320
8	8	50	321
9	9	57	318
10	10	64	320
11	11	71	321
12	12	78	318
13	13	85	320
14	14	92	321
15	15	99	318
16	16	106	320
17	17	113	321
18	18	120	318
19	19	127	320
20	20	134	321
21	21	141	318
22	22	148	320
23	23	155	321
24	24	3	318
25	25	10	320
26	26	17	321
27	27	24	318
28	28	31	320
29	29	38	321
30	30	45	318
31	31	52	320
32	32	59	321
33	33	66	318
34	34	73	320
35	35	80	321
36	36	87	318
37	37	94	320
38	38	101	321
39	39	108	318
40	40	115	320
41	41	122	321
42	42	129	318
43	43	136	320
44	44	143	321
45	45	150	318
46	46	157	320
47	47	5	321
48	48	12	318
49	49	19	320
50	50	26	321
51	51	33	318
52	52	40	320
53	53	47	321
54	54	54	318
55	55	61	320
56	56	68	321
57	57	75	318
58	58	82	320
59	59	89	321
60	60	96	318
61	61	103	320
62	62	110	321
63	63	117	318
64	64	124	320
65	65	131	321
66	66	138	318
67	67	145	320
68	68	152	321
69	69	159	318
70	70	7	320
71	71	14	321
72	72	21	318
73	73	28	320
74	74	35	321
75	75	42	318
76	76	49	320
77	77	56	321
78	78	63	318
79	79	70	320
80	80	77	321
81	81	84	318
82	82	91	320
83	83	98	321
84	84	105	318
85	85	112	320
86	86	119	321
87	87	126	318
88	88	133	320
89	89	140	321
90	90	147	318
91	91	154	320
92	92	2	321
93	93	9	318
94	94	16	320
95	95	23	321
96	96	30	318
97	97	37	320
98	98	44	321
99	99	51	318
100	100	58	320
101	101	65	321
102	102	72	318
103	103	79	320
104	104	86	321
105	105	93	318
106	106	100	320
107	107	107	321
108	108	114	318
109	109	121	320
110	110	128	321
111	111	135	318
112	112	142	320
113	113	149	321
114	114	156	318
115	115	4	320
116	116	11	321
117	117	18	318
118	118	25	320
119	119	32	321
120	120	39	318
121	121	46	320
122	122	53	321
123	123	60	318
124	124	67	320
125	125	74	321
126	126	81	318
127	127	88	320
128	128	95	321
129	129	102	318
130	130	109	320
131	131	116	321
132	132	123	318
133	133	130	320
134	134	137	321
135	135	144	318
136	136	151	320
137	137	158	321
138	138	6	318
139	139	13	320
140	140	20	321
141	141	27	318
142	142	34	320
143	143	41	321
144	144	48	318
145	145	55	320
146	146	62	321
147	147	69	318
148	148	76	320
149	149	83	321
150	150	90	318
151	151	97	320
152	152	104	321
153	153	111	318
154	154	118	320
155	155	125	321
156	156	132	318
157	157	139	320
158	158	146	321
159	159	153	318
160	160	1	320
161	161	8	321
162	162	15	318
163	163	22	320
164	164	29	321
165	165	36	318
166	166	43	320
167	167	50	321
168	168	57	318
169	169	64	320
170	170	71	321
171	171	78	318
172	172	85	320
173	173	92	321
174	174	99	318
175	175	106	320
176	176	113	321
177	177	120	318
178	178	127	320
179	179	134	321
180	180	141	318
181	181	148	320
182	182	155	321
183	183	3	318
184	184	10	320
185	185	17	321
186	186	24	318
187	187	31	320
188	188	38	321
189	189	45	318
190	190	52	320
191	191	59	321
192	192	66	318
193	193	73	320
194	194	80	321
195	195	87	318
196	196	94	320
197	197	101	321
198	198	108	318
199	199	115	320
200	200	122	321
201	201	129	318
202	202	136	320
203	203	143	321
204	204	150	318
205	205	157	320
206	206	5	321
207	207	12	318
208	208	19	320
209	209	26	321
210	210	33	318
211	211	40	320
212	212	47	321
213	213	54	318
214	214	61	320
215	215	68	321
216	216	75	318
217	217	82	320
218	218	89	321
219	219	96	318
220	220	103	320
221	221	110	321
222	222	117	318
223	223	124	320
224	224	131	321
225	225	138	318
226	226	145	320
227	227	152	321
228	228	159	318
229	229	7	320
230	230	14	321
231	231	21	318
232	232	28	320
233	233	35	321
234	234	42	318
235	235	49	320
236	236	56	321
237	237	63	318
238	238	70	320
239	239	77	321
240	240	84	318
241	241	91	320
242	242	98	321
243	243	105	318
244	244	112	320
245	245	119	321
246	246	126	318
247	247	133	320
248	248	140	321
249	249	147	318
250	250	154	320
251	251	2	321
252	252	9	318
253	253	16	320
254	254	23	321
255	255	30	318
256	256	37	320
257	257	44	321
258	258	51	318
259	259	58	320
260	260	65	321
261	261	72	318
262	262	79	320
263	263	86	321
264	264	93	318
265	265	100	320
266	266	107	321
267	267	114	318
268	268	121	320
269	269	128	321
270	270	135	318
271	271	142	320
272	272	149	321
273	273	156	318
274	274	4	320
275	275	11	321
276	276	18	318
277	277	25	320
278	278	32	321
279	279	39	318
280	280	46	320
281	281	53	321
282	282	60	318
283	283	67	320
284	284	74	321
285	285	81	318
286	286	88	320
287	287	95	321
288	288	102	318
289	289	109	320
290	290	116	321
291	291	123	318
292	292	130	320
293	293	137	321
294	294	144	318
295	295	151	320
296	296	158	321
297	297	6	318
298	298	13	320
299	299	20	321
300	300	27	318
301	1	2	321
302	2	9	318
303	3	16	320
304	4	23	321
305	5	30	318
306	6	37	320
307	7	44	321
308	8	51	318
309	9	58	320
310	10	65	321
311	11	72	318
312	12	79	320
313	13	86	321
314	14	93	318
315	15	100	320
316	16	107	321
317	17	114	318
318	18	121	320
319	19	128	321
320	20	135	318
321	21	142	320
322	22	149	321
323	23	156	318
324	24	4	320
325	25	11	321
326	26	18	318
327	27	25	320
328	28	32	321
329	29	39	318
330	30	46	320
331	31	53	321
332	32	60	318
333	33	67	320
334	34	74	321
335	35	81	318
336	36	88	320
337	37	95	321
338	38	102	318
339	39	109	320
340	40	116	321
341	41	123	318
342	42	130	320
343	43	137	321
344	44	144	318
345	45	151	320
346	46	158	321
347	47	6	318
348	48	13	320
349	49	20	321
350	50	27	318
351	51	34	320
352	52	41	321
353	53	48	318
354	54	55	320
355	55	62	321
356	56	69	318
357	57	76	320
358	58	83	321
359	59	90	318
360	60	97	320
361	61	104	321
362	62	111	318
363	63	118	320
364	64	125	321
365	65	132	318
366	66	139	320
367	67	146	321
368	68	153	318
369	69	1	320
370	70	8	321
371	71	15	318
372	72	22	320
373	73	29	321
374	74	36	318
375	75	43	320
376	76	50	321
377	77	57	318
378	78	64	320
379	79	71	321
380	80	78	318
381	81	85	320
382	82	92	321
383	83	99	318
384	84	106	320
385	85	113	321
386	86	120	318
387	87	127	320
388	88	134	321
389	89	141	318
390	90	148	320
391	91	155	321
392	92	3	318
393	93	10	320
394	94	17	321
395	95	24	318
396	96	31	320
397	97	38	321
398	98	45	318
399	99	52	320
400	100	59	321
401	101	66	318
402	102	73	320
403	103	80	321
404	104	87	318
405	105	94	320
406	106	101	321
407	107	108	318
408	108	115	320
409	109	122	321
410	110	129	318
411	111	136	320
412	112	143	321
413	113	150	318
414	114	157	320
415	115	5	321
416	116	12	318
417	117	19	320
418	118	26	321
419	119	33	318
420	120	40	320
421	121	47	321
422	122	54	318
423	123	61	320
424	124	68	321
425	125	75	318
426	126	82	320
427	127	89	321
428	128	96	318
429	129	103	320
430	130	110	321
431	131	117	318
432	132	124	320
433	133	131	321
434	134	138	318
435	135	145	320
436	136	152	321
437	137	159	318
438	138	7	320
439	139	14	321
440	140	21	318
441	141	28	320
442	142	35	321
443	143	42	318
444	144	49	320
445	145	56	321
446	146	63	318
447	147	70	320
448	148	77	321
449	149	84	318
450	150	91	320
451	151	98	321
452	152	105	318
453	153	112	320
454	154	119	321
455	155	126	318
456	156	133	320
457	157	140	321
458	158	147	318
459	159	154	320
460	160	2	321
461	161	9	318
462	162	16	320
463	163	23	321
464	164	30	318
465	165	37	320
466	166	44	321
467	167	51	318
468	168	58	320
469	169	65	321
470	170	72	318
471	171	79	320
472	172	86	321
473	173	93	318
474	174	100	320
475	175	107	321
476	176	114	318
477	177	121	320
478	178	128	321
479	179	135	318
480	180	142	320
481	181	149	321
482	182	156	318
483	183	4	320
484	184	11	321
485	185	18	318
486	186	25	320
487	187	32	321
488	188	39	318
489	189	46	320
490	190	53	321
491	191	60	318
492	192	67	320
493	193	74	321
494	194	81	318
495	195	88	320
496	196	95	321
497	197	102	318
498	198	109	320
499	199	116	321
500	200	123	318
501	201	130	320
502	202	137	321
503	203	144	318
504	204	151	320
505	205	158	321
506	206	6	318
507	207	13	320
508	208	20	321
509	209	27	318
510	210	34	320
511	211	41	321
512	212	48	318
513	213	55	320
514	214	62	321
515	215	69	318
516	216	76	320
517	217	83	321
518	218	90	318
519	219	97	320
520	220	104	321
521	221	111	318
522	222	118	320
523	223	125	321
524	224	132	318
525	225	139	320
526	226	146	321
527	227	153	318
528	228	1	320
529	229	8	321
530	230	15	318
531	231	22	320
532	232	29	321
533	233	36	318
534	234	43	320
535	235	50	321
536	236	57	318
537	237	64	320
538	238	71	321
539	239	78	318
540	240	85	320
541	241	92	321
542	242	99	318
543	243	106	320
544	244	113	321
545	245	120	318
546	246	127	320
547	247	134	321
548	248	141	318
549	249	148	320
550	250	155	321
551	251	3	318
552	252	10	320
553	253	17	321
554	254	24	318
555	255	31	320
556	256	38	321
557	257	45	318
558	258	52	320
559	259	59	321
560	260	66	318
561	261	73	320
562	262	80	321
563	263	87	318
564	264	94	320
565	265	101	321
566	266	108	318
567	267	115	320
568	268	122	321
569	269	129	318
570	270	136	320
571	271	143	321
572	272	150	318
573	273	157	320
574	274	5	321
575	275	12	318
576	276	19	320
577	277	26	321
578	278	33	318
579	279	40	320
580	280	47	321
581	281	54	318
582	282	61	320
583	283	68	321
584	284	75	318
585	285	82	320
586	286	89	321
587	287	96	318
588	288	103	320
589	289	110	321
590	290	117	318
591	291	124	320
592	292	131	321
593	293	138	318
594	294	145	320
595	295	152	321
596	296	159	318
597	297	7	320
598	298	14	321
599	299	21	318
600	300	28	320
601	1	3	318
602	2	10	320
603	3	17	321
604	4	24	318
605	5	31	320
606	6	38	321
607	7	45	318
608	8	52	320
609	9	59	321
610	10	66	318
611	11	73	320
612	12	80	321
613	13	87	318
614	14	94	320
615	15	101	321
616	16	108	318
617	17	115	320
618	18	122	321
619	19	129	318
620	20	136	320
621	21	143	321
622	22	150	318
623	23	157	320
624	24	5	321
625	25	12	318
626	26	19	320
627	27	26	321
628	28	33	318
629	29	40	320
630	30	47	321
631	31	54	318
632	32	61	320
633	33	68	321
634	34	75	318
635	35	82	320
636	36	89	321
637	37	96	318
638	38	103	320
639	39	110	321
640	40	117	318
641	41	124	320
642	42	131	321
643	43	138	318
644	44	145	320
645	45	152	321
646	46	159	318
647	47	7	320
648	48	14	321
649	49	21	318
650	50	28	320
651	51	35	321
652	52	42	318
653	53	49	320
654	54	56	321
655	55	63	318
656	56	70	320
657	57	77	321
658	58	84	318
659	59	91	320
660	60	98	321
661	61	105	318
662	62	112	320
663	63	119	321
664	64	126	318
665	65	133	320
666	66	140	321
667	67	147	318
668	68	154	320
669	69	2	321
670	70	9	318
671	71	16	320
672	72	23	321
673	73	30	318
674	74	37	320
675	75	44	321
676	76	51	318
677	77	58	320
678	78	65	321
679	79	72	318
680	80	79	320
681	81	86	321
682	82	93	318
683	83	100	320
684	84	107	321
685	85	114	318
686	86	121	320
687	87	128	321
688	88	135	318
689	89	142	320
690	90	149	321
691	91	156	318
692	92	4	320
693	93	11	321
694	94	18	318
695	95	25	320
696	96	32	321
697	97	39	318
698	98	46	320
699	99	53	321
700	100	60	318
701	101	67	320
702	102	74	321
703	103	81	318
704	104	88	320
705	105	95	321
706	106	102	318
707	107	109	320
708	108	116	321
709	109	123	318
710	110	130	320
711	111	137	321
712	112	144	318
713	113	151	320
714	114	158	321
715	115	6	318
716	116	13	320
717	117	20	321
718	118	27	318
719	119	34	320
720	120	41	321
721	121	48	318
722	122	55	320
723	123	62	321
724	124	69	318
725	125	76	320
726	126	83	321
727	127	90	318
728	128	97	320
729	129	104	321
730	130	111	318
731	131	118	320
732	132	125	321
733	133	132	318
734	134	139	320
735	135	146	321
736	136	153	318
737	137	1	320
738	138	8	321
739	139	15	318
740	140	22	320
741	141	29	321
742	142	36	318
743	143	43	320
744	144	50	321
745	145	57	318
746	146	64	320
747	147	71	321
748	148	78	318
749	149	85	320
750	150	92	321
751	151	99	318
752	152	106	320
753	153	113	321
754	154	120	318
755	155	127	320
756	156	134	321
757	157	141	318
758	158	148	320
759	159	155	321
760	160	3	318
761	161	10	320
762	162	17	321
763	163	24	318
764	164	31	320
765	165	38	321
766	166	45	318
767	167	52	320
768	168	59	321
769	169	66	318
770	170	73	320
771	171	80	321
772	172	87	318
773	173	94	320
774	174	101	321
775	175	108	318
776	176	115	320
777	177	122	321
778	178	129	318
779	179	136	320
780	180	143	321
781	181	150	318
782	182	157	320
783	183	5	321
784	184	12	318
785	185	19	320
786	186	26	321
787	187	33	318
788	188	40	320
789	189	47	321
790	190	54	318
791	191	61	320
792	192	68	321
793	193	75	318
794	194	82	320
795	195	89	321
796	196	96	318
797	197	103	320
798	198	110	321
799	199	117	318
800	200	124	320
801	201	131	321
802	202	138	318
803	203	145	320
804	204	152	321
805	205	159	318
806	206	7	320
807	207	14	321
808	208	21	318
809	209	28	320
810	210	35	321
811	211	42	318
812	212	49	320
813	213	56	321
814	214	63	318
815	215	70	320
816	216	77	321
817	217	84	318
818	218	91	320
819	219	98	321
820	220	105	318
821	221	112	320
822	222	119	321
823	223	126	318
824	224	133	320
825	225	140	321
826	226	147	318
827	227	154	320
828	228	2	321
829	229	9	318
830	230	16	320
831	231	23	321
832	232	30	318
833	233	37	320
834	234	44	321
835	235	51	318
836	236	58	320
837	237	65	321
838	238	72	318
839	239	79	320
840	240	86	321
841	241	93	318
842	242	100	320
843	243	107	321
844	244	114	318
845	245	121	320
846	246	128	321
847	247	135	318
848	248	142	320
849	249	149	321
850	250	156	318
851	251	4	320
852	252	11	321
853	253	18	318
854	254	25	320
855	255	32	321
856	256	39	318
857	257	46	320
858	258	53	321
859	259	60	318
860	260	67	320
861	261	74	321
862	262	81	318
863	263	88	320
864	264	95	321
865	265	102	318
866	266	109	320
867	267	116	321
868	268	123	318
869	269	130	320
870	270	137	321
871	271	144	318
872	272	151	320
873	273	158	321
874	274	6	318
875	275	13	320
876	276	20	321
877	277	27	318
878	278	34	320
879	279	41	321
880	280	48	318
881	281	55	320
882	282	62	321
883	283	69	318
884	284	76	320
885	285	83	321
886	286	90	318
887	287	97	320
888	288	104	321
889	289	111	318
890	290	118	320
891	291	125	321
892	292	132	318
893	293	139	320
894	294	146	321
895	295	153	318
896	296	1	320
897	297	8	321
898	298	15	318
899	299	22	320
900	300	29	321
901	1	4	320
902	2	11	321
903	3	18	318
904	4	25	320
905	5	32	321
906	6	39	318
907	7	46	320
908	8	53	321
909	9	60	318
910	10	67	320
911	11	74	321
912	12	81	318
913	13	88	320
914	14	95	321
915	15	102	318
916	16	109	320
917	17	116	321
918	18	123	318
919	19	130	320
920	20	137	321
921	21	144	318
922	22	151	320
923	23	158	321
924	24	6	318
925	25	13	320
926	26	20	321
927	27	27	318
928	28	34	320
929	29	41	321
930	30	48	318
931	31	55	320
932	32	62	321
933	33	69	318
934	34	76	320
935	35	83	321
936	36	90	318
937	37	97	320
938	38	104	321
939	39	111	318
940	40	118	320
941	41	125	321
942	42	132	318
943	43	139	320
944	44	146	321
945	45	153	318
946	46	1	320
947	47	8	321
948	48	15	318
949	49	22	320
950	50	29	321
951	51	36	318
952	52	43	320
953	53	50	321
954	54	57	318
955	55	64	320
956	56	71	321
957	57	78	318
958	58	85	320
959	59	92	321
960	60	99	318
961	61	106	320
962	62	113	321
963	63	120	318
964	64	127	320
965	65	134	321
966	66	141	318
967	67	148	320
968	68	155	321
969	69	3	318
970	70	10	320
971	71	17	321
972	72	24	318
973	73	31	320
974	74	38	321
975	75	45	318
976	76	52	320
977	77	59	321
978	78	66	318
979	79	73	320
980	80	80	321
981	81	87	318
982	82	94	320
983	83	101	321
984	84	108	318
985	85	115	320
986	86	122	321
987	87	129	318
988	88	136	320
989	89	143	321
990	90	150	318
991	91	157	320
992	92	5	321
993	93	12	318
994	94	19	320
995	95	26	321
996	96	33	318
997	97	40	320
998	98	47	321
999	99	54	318
1000	100	61	320
1001	101	68	321
1002	102	75	318
1003	103	82	320
1004	104	89	321
1005	105	96	318
1006	106	103	320
1007	107	110	321
1008	108	117	318
1009	109	124	320
1010	110	131	321
1011	111	138	318
1012	112	145	320
1013	113	152	321
1014	114	159	318
1015	115	7	320
1016	116	14	321
1017	117	21	318
1018	118	28	320
1019	119	35	321
1020	120	42	318
1021	121	49	320
1022	122	56	321
1023	123	63	318
1024	124	70	320
1025	125	77	321
1026	126	84	318
1027	127	91	320
1028	128	98	321
1029	129	105	318
1030	130	112	320
1031	131	119	321
1032	132	126	318
1033	133	133	320
1034	134	140	321
1035	135	147	318
1036	136	154	320
1037	137	2	321
1038	138	9	318
1039	139	16	320
1040	140	23	321
1041	141	30	318
1042	142	37	320
1043	143	44	321
1044	144	51	318
1045	145	58	320
1046	146	65	321
1047	147	72	318
1048	148	79	320
1049	149	86	321
1050	150	93	318
1051	151	100	320
1052	152	107	321
1053	153	114	318
1054	154	121	320
1055	155	128	321
1056	156	135	318
1057	157	142	320
1058	158	149	321
1059	159	156	318
1060	160	4	320
1061	161	11	321
1062	162	18	318
1063	163	25	320
1064	164	32	321
1065	165	39	318
1066	166	46	320
1067	167	53	321
1068	168	60	318
1069	169	67	320
1070	170	74	321
1071	171	81	318
1072	172	88	320
1073	173	95	321
1074	174	102	318
1075	175	109	320
1076	176	116	321
1077	177	123	318
1078	178	130	320
1079	179	137	321
1080	180	144	318
1081	181	151	320
1082	182	158	321
1083	183	6	318
1084	184	13	320
1085	185	20	321
1086	186	27	318
1087	187	34	320
1088	188	41	321
1089	189	48	318
1090	190	55	320
1091	191	62	321
1092	192	69	318
1093	193	76	320
1094	194	83	321
1095	195	90	318
1096	196	97	320
1097	197	104	321
1098	198	111	318
1099	199	118	320
1100	200	125	321
1101	201	132	318
1102	202	139	320
1103	203	146	321
1104	204	153	318
1105	205	1	320
1106	206	8	321
1107	207	15	318
1108	208	22	320
1109	209	29	321
1110	210	36	318
1111	211	43	320
1112	212	50	321
1113	213	57	318
1114	214	64	320
1115	215	71	321
1116	216	78	318
1117	217	85	320
1118	218	92	321
1119	219	99	318
1120	220	106	320
1121	221	113	321
1122	222	120	318
1123	223	127	320
1124	224	134	321
1125	225	141	318
1126	226	148	320
1127	227	155	321
1128	228	3	318
1129	229	10	320
1130	230	17	321
1131	231	24	318
1132	232	31	320
1133	233	38	321
1134	234	45	318
1135	235	52	320
1136	236	59	321
1137	237	66	318
1138	238	73	320
1139	239	80	321
1140	240	87	318
1141	241	94	320
1142	242	101	321
1143	243	108	318
1144	244	115	320
1145	245	122	321
1146	246	129	318
1147	247	136	320
1148	248	143	321
1149	249	150	318
1150	250	157	320
1151	251	5	321
1152	252	12	318
1153	253	19	320
1154	254	26	321
1155	255	33	318
1156	256	40	320
1157	257	47	321
1158	258	54	318
1159	259	61	320
1160	260	68	321
1161	261	75	318
1162	262	82	320
1163	263	89	321
1164	264	96	318
1165	265	103	320
1166	266	110	321
1167	267	117	318
1168	268	124	320
1169	269	131	321
1170	270	138	318
1171	271	145	320
1172	272	152	321
1173	273	159	318
1174	274	7	320
1175	275	14	321
1176	276	21	318
1177	277	28	320
1178	278	35	321
1179	279	42	318
1180	280	49	320
1181	281	56	321
1182	282	63	318
1183	283	70	320
1184	284	77	321
1185	285	84	318
1186	286	91	320
1187	287	98	321
1188	288	105	318
1189	289	112	320
1190	290	119	321
1191	291	126	318
1192	292	133	320
1193	293	140	321
1194	294	147	318
1195	295	154	320
1196	296	2	321
1197	297	9	318
1198	298	16	320
1199	299	23	321
1200	300	30	318
1201	1	5	321
1202	2	12	318
1203	3	19	320
1204	4	26	321
1205	5	33	318
1206	6	40	320
1207	7	47	321
1208	8	54	318
1209	9	61	320
1210	10	68	321
1211	11	75	318
1212	12	82	320
1213	13	89	321
1214	14	96	318
1215	15	103	320
1216	16	110	321
1217	17	117	318
1218	18	124	320
1219	19	131	321
1220	20	138	318
1221	21	145	320
1222	22	152	321
1223	23	159	318
1224	24	7	320
1225	25	14	321
1226	26	21	318
1227	27	28	320
1228	28	35	321
1229	29	42	318
1230	30	49	320
1231	31	56	321
1232	32	63	318
1233	33	70	320
1234	34	77	321
1235	35	84	318
1236	36	91	320
1237	37	98	321
1238	38	105	318
1239	39	112	320
1240	40	119	321
1241	41	126	318
1242	42	133	320
1243	43	140	321
1244	44	147	318
1245	45	154	320
1246	46	2	321
1247	47	9	318
1248	48	16	320
1249	49	23	321
1250	50	30	318
1251	51	37	320
1252	52	44	321
1253	53	51	318
1254	54	58	320
1255	55	65	321
1256	56	72	318
1257	57	79	320
1258	58	86	321
1259	59	93	318
1260	60	100	320
1261	61	107	321
1262	62	114	318
1263	63	121	320
1264	64	128	321
1265	65	135	318
1266	66	142	320
1267	67	149	321
1268	68	156	318
1269	69	4	320
1270	70	11	321
1271	71	18	318
1272	72	25	320
1273	73	32	321
1274	74	39	318
1275	75	46	320
1276	76	53	321
1277	77	60	318
1278	78	67	320
1279	79	74	321
1280	80	81	318
1281	81	88	320
1282	82	95	321
1283	83	102	318
1284	84	109	320
1285	85	116	321
1286	86	123	318
1287	87	130	320
1288	88	137	321
1289	89	144	318
1290	90	151	320
1291	91	158	321
1292	92	6	318
1293	93	13	320
1294	94	20	321
1295	95	27	318
1296	96	34	320
1297	97	41	321
1298	98	48	318
1299	99	55	320
1300	100	62	321
1301	101	69	318
1302	102	76	320
1303	103	83	321
1304	104	90	318
1305	105	97	320
1306	106	104	321
1307	107	111	318
1308	108	118	320
1309	109	125	321
1310	110	132	318
1311	111	139	320
1312	112	146	321
1313	113	153	318
1314	114	1	320
1315	115	8	321
1316	116	15	318
1317	117	22	320
1318	118	29	321
1319	119	36	318
1320	120	43	320
1321	121	50	321
1322	122	57	318
1323	123	64	320
1324	124	71	321
1325	125	78	318
1326	126	85	320
1327	127	92	321
1328	128	99	318
1329	129	106	320
1330	130	113	321
1331	131	120	318
1332	132	127	320
1333	133	134	321
1334	134	141	318
1335	135	148	320
1336	136	155	321
1337	137	3	318
1338	138	10	320
1339	139	17	321
1340	140	24	318
1341	141	31	320
1342	142	38	321
1343	143	45	318
1344	144	52	320
1345	145	59	321
1346	146	66	318
1347	147	73	320
1348	148	80	321
1349	149	87	318
1350	150	94	320
1351	151	101	321
1352	152	108	318
1353	153	115	320
1354	154	122	321
1355	155	129	318
1356	156	136	320
1357	157	143	321
1358	158	150	318
1359	159	157	320
1360	160	5	321
1361	161	12	318
1362	162	19	320
1363	163	26	321
1364	164	33	318
1365	165	40	320
1366	166	47	321
1367	167	54	318
1368	168	61	320
1369	169	68	321
1370	170	75	318
1371	171	82	320
1372	172	89	321
1373	173	96	318
1374	174	103	320
1375	175	110	321
1376	176	117	318
1377	177	124	320
1378	178	131	321
1379	179	138	318
1380	180	145	320
1381	181	152	321
1382	182	159	318
1383	183	7	320
1384	184	14	321
1385	185	21	318
1386	186	28	320
1387	187	35	321
1388	188	42	318
1389	189	49	320
1390	190	56	321
1391	191	63	318
1392	192	70	320
1393	193	77	321
1394	194	84	318
1395	195	91	320
1396	196	98	321
1397	197	105	318
1398	198	112	320
1399	199	119	321
1400	200	126	318
1401	201	133	320
1402	202	140	321
1403	203	147	318
1404	204	154	320
1405	205	2	321
1406	206	9	318
1407	207	16	320
1408	208	23	321
1409	209	30	318
1410	210	37	320
1411	211	44	321
1412	212	51	318
1413	213	58	320
1414	214	65	321
1415	215	72	318
1416	216	79	320
1417	217	86	321
1418	218	93	318
1419	219	100	320
1420	220	107	321
1421	221	114	318
1422	222	121	320
1423	223	128	321
1424	224	135	318
1425	225	142	320
1426	226	149	321
1427	227	156	318
1428	228	4	320
1429	229	11	321
1430	230	18	318
1431	231	25	320
1432	232	32	321
1433	233	39	318
1434	234	46	320
1435	235	53	321
1436	236	60	318
1437	237	67	320
1438	238	74	321
1439	239	81	318
1440	240	88	320
1441	241	95	321
1442	242	102	318
1443	243	109	320
1444	244	116	321
1445	245	123	318
1446	246	130	320
1447	247	137	321
1448	248	144	318
1449	249	151	320
1450	250	158	321
1451	251	6	318
1452	252	13	320
1453	253	20	321
1454	254	27	318
1455	255	34	320
1456	256	41	321
1457	257	48	318
1458	258	55	320
1459	259	62	321
1460	260	69	318
1461	261	76	320
1462	262	83	321
1463	263	90	318
1464	264	97	320
1465	265	104	321
1466	266	111	318
1467	267	118	320
1468	268	125	321
1469	269	132	318
1470	270	139	320
1471	271	146	321
1472	272	153	318
1473	273	1	320
1474	274	8	321
1475	275	15	318
1476	276	22	320
1477	277	29	321
1478	278	36	318
1479	279	43	320
1480	280	50	321
1481	281	57	318
1482	282	64	320
1483	283	71	321
1484	284	78	318
1485	285	85	320
1486	286	92	321
1487	287	99	318
1488	288	106	320
1489	289	113	321
1490	290	120	318
1491	291	127	320
1492	292	134	321
1493	293	141	318
1494	294	148	320
1495	295	155	321
1496	296	3	318
1497	297	10	320
1498	298	17	321
1499	299	24	318
1500	300	31	320
\.


--
-- TOC entry 3639 (class 0 OID 95871)
-- Dependencies: 241
-- Data for Name: talentos; Type: TABLE DATA; Schema: InHire; Owner: postgres
--

COPY "InHire".talentos (id, nome_abreviado, id_cargo, id_senioridade, id_modalidade, disponibilidade_informada_percentual, status, criado_em) FROM stdin;
1	Lucas Almeida	81	154	149	60	t	2026-10-27 20:07:30.3217+00
2	Mariana Almeida	88	151	149	10	t	2026-10-27 20:07:30.3217+00
3	Rafael Almeida	95	156	149	70	t	2026-10-27 20:07:30.3217+00
4	Camila Almeida	102	153	149	20	t	2026-10-27 20:07:30.3217+00
5	André Almeida	109	150	149	80	t	2026-10-27 20:07:30.3217+00
6	Juliana Almeida	116	155	149	30	t	2026-10-27 20:07:30.3217+00
7	Felipe Almeida	123	152	149	90	t	2026-10-27 20:07:30.3217+00
8	Beatriz Almeida	130	157	149	40	t	2026-10-27 20:07:30.3217+00
9	Gabriel Almeida	137	154	149	100	t	2026-10-27 20:07:30.3217+00
10	Larissa Almeida	78	151	149	50	t	2026-10-27 20:07:30.3217+00
11	Thiago Almeida	85	156	149	0	t	2026-10-27 20:07:30.3217+00
12	Renata Almeida	92	153	149	60	t	2026-10-27 20:07:30.3217+00
13	Bruno Almeida	99	150	149	10	t	2026-10-27 20:07:30.3217+00
14	Patricia Almeida	106	155	149	70	t	2026-10-27 20:07:30.3217+00
15	Daniel Almeida	113	152	149	20	t	2026-10-27 20:07:30.3217+00
16	Fernanda Almeida	120	157	149	80	t	2026-10-27 20:07:30.3217+00
17	Eduardo Almeida	127	154	149	30	t	2026-10-27 20:07:30.3217+00
18	Amanda Almeida	134	151	149	90	t	2026-10-27 20:07:30.3217+00
19	Rodrigo Almeida	75	156	149	40	f	2026-10-27 20:07:30.3217+00
20	Vanessa Almeida	82	153	149	100	t	2026-10-27 20:07:30.3217+00
21	Lucas Barbosa	89	150	149	50	t	2026-10-27 20:07:30.3217+00
22	Mariana Barbosa	96	155	149	0	t	2026-10-27 20:07:30.3217+00
23	Rafael Barbosa	103	152	149	60	t	2026-10-27 20:07:30.3217+00
24	Camila Barbosa	110	157	149	10	t	2026-10-27 20:07:30.3217+00
25	André Barbosa	117	154	149	70	t	2026-10-27 20:07:30.3217+00
26	Juliana Barbosa	124	151	149	20	t	2026-10-27 20:07:30.3217+00
27	Felipe Barbosa	131	156	149	80	t	2026-10-27 20:07:30.3217+00
28	Beatriz Barbosa	138	153	149	30	t	2026-10-27 20:07:30.3217+00
29	Gabriel Barbosa	79	150	149	90	t	2026-10-27 20:07:30.3217+00
30	Larissa Barbosa	86	155	149	40	t	2026-10-27 20:07:30.3217+00
31	Thiago Barbosa	93	152	149	100	t	2026-10-27 20:07:30.3217+00
32	Renata Barbosa	100	157	149	50	t	2026-10-27 20:07:30.3217+00
33	Bruno Barbosa	107	154	149	0	t	2026-10-27 20:07:30.3217+00
34	Patricia Barbosa	114	151	149	60	t	2026-10-27 20:07:30.3217+00
35	Daniel Barbosa	121	156	149	10	t	2026-10-27 20:07:30.3217+00
36	Fernanda Barbosa	128	153	149	70	t	2026-10-27 20:07:30.3217+00
37	Eduardo Barbosa	135	150	149	20	t	2026-10-27 20:07:30.3217+00
38	Amanda Barbosa	76	155	149	80	f	2026-10-27 20:07:30.3217+00
39	Rodrigo Barbosa	83	152	149	30	t	2026-10-27 20:07:30.3217+00
40	Vanessa Barbosa	90	157	149	90	t	2026-10-27 20:07:30.3217+00
41	Lucas Carvalho	97	154	149	40	t	2026-10-27 20:07:30.3217+00
42	Mariana Carvalho	104	151	149	100	t	2026-10-27 20:07:30.3217+00
43	Rafael Carvalho	111	156	149	50	t	2026-10-27 20:07:30.3217+00
44	Camila Carvalho	118	153	149	0	t	2026-10-27 20:07:30.3217+00
45	André Carvalho	125	150	149	60	t	2026-10-27 20:07:30.3217+00
46	Juliana Carvalho	132	155	149	10	t	2026-10-27 20:07:30.3217+00
47	Felipe Carvalho	139	152	149	70	t	2026-10-27 20:07:30.3217+00
48	Beatriz Carvalho	80	157	149	20	t	2026-10-27 20:07:30.3217+00
49	Gabriel Carvalho	87	154	149	80	t	2026-10-27 20:07:30.3217+00
50	Larissa Carvalho	94	151	149	30	t	2026-10-27 20:07:30.3217+00
51	Thiago Carvalho	101	156	149	90	t	2026-10-27 20:07:30.3217+00
52	Renata Carvalho	108	153	149	40	t	2026-10-27 20:07:30.3217+00
53	Bruno Carvalho	115	150	149	100	t	2026-10-27 20:07:30.3217+00
54	Patricia Carvalho	122	155	149	50	t	2026-10-27 20:07:30.3217+00
55	Daniel Carvalho	129	152	149	0	t	2026-10-27 20:07:30.3217+00
56	Fernanda Carvalho	136	157	149	60	t	2026-10-27 20:07:30.3217+00
57	Eduardo Carvalho	77	154	149	10	f	2026-10-27 20:07:30.3217+00
58	Amanda Carvalho	84	151	149	70	t	2026-10-27 20:07:30.3217+00
59	Rodrigo Carvalho	91	156	149	20	t	2026-10-27 20:07:30.3217+00
60	Vanessa Carvalho	98	153	149	80	t	2026-10-27 20:07:30.3217+00
61	Lucas Ferreira	105	150	149	30	t	2026-10-27 20:07:30.3217+00
62	Mariana Ferreira	112	155	149	90	t	2026-10-27 20:07:30.3217+00
63	Rafael Ferreira	119	152	149	40	t	2026-10-27 20:07:30.3217+00
64	Camila Ferreira	126	157	149	100	t	2026-10-27 20:07:30.3217+00
65	André Ferreira	133	154	149	50	t	2026-10-27 20:07:30.3217+00
66	Juliana Ferreira	140	151	149	0	t	2026-10-27 20:07:30.3217+00
67	Felipe Ferreira	81	156	149	60	t	2026-10-27 20:07:30.3217+00
68	Beatriz Ferreira	88	153	149	10	t	2026-10-27 20:07:30.3217+00
69	Gabriel Ferreira	95	150	149	70	t	2026-10-27 20:07:30.3217+00
70	Larissa Ferreira	102	155	149	20	t	2026-10-27 20:07:30.3217+00
71	Thiago Ferreira	109	152	149	80	t	2026-10-27 20:07:30.3217+00
72	Renata Ferreira	116	157	149	30	t	2026-10-27 20:07:30.3217+00
73	Bruno Ferreira	123	154	149	90	t	2026-10-27 20:07:30.3217+00
74	Patricia Ferreira	130	151	149	40	t	2026-10-27 20:07:30.3217+00
75	Daniel Ferreira	137	156	149	100	t	2026-10-27 20:07:30.3217+00
76	Fernanda Ferreira	78	153	149	50	f	2026-10-27 20:07:30.3217+00
77	Eduardo Ferreira	85	150	149	0	t	2026-10-27 20:07:30.3217+00
78	Amanda Ferreira	92	155	149	60	t	2026-10-27 20:07:30.3217+00
79	Rodrigo Ferreira	99	152	149	10	t	2026-10-27 20:07:30.3217+00
80	Vanessa Ferreira	106	157	149	70	t	2026-10-27 20:07:30.3217+00
81	Lucas Gomes	113	154	149	20	t	2026-10-27 20:07:30.3217+00
82	Mariana Gomes	120	151	149	80	t	2026-10-27 20:07:30.3217+00
83	Rafael Gomes	127	156	149	30	t	2026-10-27 20:07:30.3217+00
84	Camila Gomes	134	153	149	90	t	2026-10-27 20:07:30.3217+00
85	André Gomes	75	150	149	40	t	2026-10-27 20:07:30.3217+00
86	Juliana Gomes	82	155	149	100	t	2026-10-27 20:07:30.3217+00
87	Felipe Gomes	89	152	149	50	t	2026-10-27 20:07:30.3217+00
88	Beatriz Gomes	96	157	149	0	t	2026-10-27 20:07:30.3217+00
89	Gabriel Gomes	103	154	149	60	t	2026-10-27 20:07:30.3217+00
90	Larissa Gomes	110	151	149	10	t	2026-10-27 20:07:30.3217+00
91	Thiago Gomes	117	156	149	70	t	2026-10-27 20:07:30.3217+00
92	Renata Gomes	124	153	149	20	t	2026-10-27 20:07:30.3217+00
93	Bruno Gomes	131	150	149	80	t	2026-10-27 20:07:30.3217+00
94	Patricia Gomes	138	155	149	30	t	2026-10-27 20:07:30.3217+00
95	Daniel Gomes	79	152	149	90	f	2026-10-27 20:07:30.3217+00
96	Fernanda Gomes	86	157	149	40	t	2026-10-27 20:07:30.3217+00
97	Eduardo Gomes	93	154	149	100	t	2026-10-27 20:07:30.3217+00
98	Amanda Gomes	100	151	149	50	t	2026-10-27 20:07:30.3217+00
99	Rodrigo Gomes	107	156	149	0	t	2026-10-27 20:07:30.3217+00
100	Vanessa Gomes	114	153	149	60	t	2026-10-27 20:07:30.3217+00
101	Lucas Lima	121	150	149	10	t	2026-10-27 20:07:30.3217+00
102	Mariana Lima	128	155	149	70	t	2026-10-27 20:07:30.3217+00
103	Rafael Lima	135	152	149	20	t	2026-10-27 20:07:30.3217+00
104	Camila Lima	76	157	149	80	t	2026-10-27 20:07:30.3217+00
105	André Lima	83	154	149	30	t	2026-10-27 20:07:30.3217+00
106	Juliana Lima	90	151	149	90	t	2026-10-27 20:07:30.3217+00
107	Felipe Lima	97	156	149	40	t	2026-10-27 20:07:30.3217+00
108	Beatriz Lima	104	153	149	100	t	2026-10-27 20:07:30.3217+00
109	Gabriel Lima	111	150	149	50	t	2026-10-27 20:07:30.3217+00
110	Larissa Lima	118	155	149	0	t	2026-10-27 20:07:30.3217+00
111	Thiago Lima	125	152	149	60	t	2026-10-27 20:07:30.3217+00
112	Renata Lima	132	157	149	10	t	2026-10-27 20:07:30.3217+00
113	Bruno Lima	139	154	149	70	t	2026-10-27 20:07:30.3217+00
114	Patricia Lima	80	151	149	20	f	2026-10-27 20:07:30.3217+00
115	Daniel Lima	87	156	149	80	t	2026-10-27 20:07:30.3217+00
116	Fernanda Lima	94	153	149	30	t	2026-10-27 20:07:30.3217+00
117	Eduardo Lima	101	150	149	90	t	2026-10-27 20:07:30.3217+00
118	Amanda Lima	108	155	149	40	t	2026-10-27 20:07:30.3217+00
119	Rodrigo Lima	115	152	149	100	t	2026-10-27 20:07:30.3217+00
120	Vanessa Lima	122	157	149	50	t	2026-10-27 20:07:30.3217+00
121	Lucas Martins	129	154	149	0	t	2026-10-27 20:07:30.3217+00
122	Mariana Martins	136	151	149	60	t	2026-10-27 20:07:30.3217+00
123	Rafael Martins	77	156	149	10	t	2026-10-27 20:07:30.3217+00
124	Camila Martins	84	153	149	70	t	2026-10-27 20:07:30.3217+00
125	André Martins	91	150	149	20	t	2026-10-27 20:07:30.3217+00
126	Juliana Martins	98	155	149	80	t	2026-10-27 20:07:30.3217+00
127	Felipe Martins	105	152	149	30	t	2026-10-27 20:07:30.3217+00
128	Beatriz Martins	112	157	149	90	t	2026-10-27 20:07:30.3217+00
129	Gabriel Martins	119	154	149	40	t	2026-10-27 20:07:30.3217+00
130	Larissa Martins	126	151	149	100	t	2026-10-27 20:07:30.3217+00
131	Thiago Martins	133	156	149	50	t	2026-10-27 20:07:30.3217+00
132	Renata Martins	140	153	149	0	t	2026-10-27 20:07:30.3217+00
133	Bruno Martins	81	150	149	60	f	2026-10-27 20:07:30.3217+00
134	Patricia Martins	88	155	149	10	t	2026-10-27 20:07:30.3217+00
135	Daniel Martins	95	152	149	70	t	2026-10-27 20:07:30.3217+00
136	Fernanda Martins	102	157	149	20	t	2026-10-27 20:07:30.3217+00
137	Eduardo Martins	109	154	149	80	t	2026-10-27 20:07:30.3217+00
138	Amanda Martins	116	151	149	30	t	2026-10-27 20:07:30.3217+00
139	Rodrigo Martins	123	156	149	90	t	2026-10-27 20:07:30.3217+00
140	Vanessa Martins	130	153	149	40	t	2026-10-27 20:07:30.3217+00
141	Lucas Monteiro	137	150	149	100	t	2026-10-27 20:07:30.3217+00
142	Mariana Monteiro	78	155	149	50	t	2026-10-27 20:07:30.3217+00
143	Rafael Monteiro	85	152	149	0	t	2026-10-27 20:07:30.3217+00
144	Camila Monteiro	92	157	149	60	t	2026-10-27 20:07:30.3217+00
145	André Monteiro	99	154	149	10	t	2026-10-27 20:07:30.3217+00
146	Juliana Monteiro	106	151	149	70	t	2026-10-27 20:07:30.3217+00
147	Felipe Monteiro	113	156	149	20	t	2026-10-27 20:07:30.3217+00
148	Beatriz Monteiro	120	153	149	80	t	2026-10-27 20:07:30.3217+00
149	Gabriel Monteiro	127	150	149	30	t	2026-10-27 20:07:30.3217+00
150	Larissa Monteiro	134	155	149	90	t	2026-10-27 20:07:30.3217+00
151	Thiago Monteiro	75	152	149	40	t	2026-10-27 20:07:30.3217+00
152	Renata Monteiro	82	157	149	100	f	2026-10-27 20:07:30.3217+00
153	Bruno Monteiro	89	154	149	50	t	2026-10-27 20:07:30.3217+00
154	Patricia Monteiro	96	151	149	0	t	2026-10-27 20:07:30.3217+00
155	Daniel Monteiro	103	156	149	60	t	2026-10-27 20:07:30.3217+00
156	Fernanda Monteiro	110	153	149	10	t	2026-10-27 20:07:30.3217+00
157	Eduardo Monteiro	117	150	149	70	t	2026-10-27 20:07:30.3217+00
158	Amanda Monteiro	124	155	149	20	t	2026-10-27 20:07:30.3217+00
159	Rodrigo Monteiro	131	152	149	80	t	2026-10-27 20:07:30.3217+00
160	Vanessa Monteiro	138	157	149	30	t	2026-10-27 20:07:30.3217+00
161	Lucas Nascimento	79	154	149	90	t	2026-10-27 20:07:30.3217+00
162	Mariana Nascimento	86	151	149	40	t	2026-10-27 20:07:30.3217+00
163	Rafael Nascimento	93	156	149	100	t	2026-10-27 20:07:30.3217+00
164	Camila Nascimento	100	153	149	50	t	2026-10-27 20:07:30.3217+00
165	André Nascimento	107	150	149	0	t	2026-10-27 20:07:30.3217+00
166	Juliana Nascimento	114	155	149	60	t	2026-10-27 20:07:30.3217+00
167	Felipe Nascimento	121	152	149	10	t	2026-10-27 20:07:30.3217+00
168	Beatriz Nascimento	128	157	149	70	t	2026-10-27 20:07:30.3217+00
169	Gabriel Nascimento	135	154	149	20	t	2026-10-27 20:07:30.3217+00
170	Larissa Nascimento	76	151	149	80	t	2026-10-27 20:07:30.3217+00
171	Thiago Nascimento	83	156	149	30	f	2026-10-27 20:07:30.3217+00
172	Renata Nascimento	90	153	149	90	t	2026-10-27 20:07:30.3217+00
173	Bruno Nascimento	97	150	149	40	t	2026-10-27 20:07:30.3217+00
174	Patricia Nascimento	104	155	149	100	t	2026-10-27 20:07:30.3217+00
175	Daniel Nascimento	111	152	149	50	t	2026-10-27 20:07:30.3217+00
176	Fernanda Nascimento	118	157	149	0	t	2026-10-27 20:07:30.3217+00
177	Eduardo Nascimento	125	154	149	60	t	2026-10-27 20:07:30.3217+00
178	Amanda Nascimento	132	151	149	10	t	2026-10-27 20:07:30.3217+00
179	Rodrigo Nascimento	139	156	149	70	t	2026-10-27 20:07:30.3217+00
180	Vanessa Nascimento	80	153	149	20	t	2026-10-27 20:07:30.3217+00
181	Lucas Oliveira	87	150	149	80	t	2026-10-27 20:07:30.3217+00
182	Mariana Oliveira	94	155	149	30	t	2026-10-27 20:07:30.3217+00
183	Rafael Oliveira	101	152	149	90	t	2026-10-27 20:07:30.3217+00
184	Camila Oliveira	108	157	149	40	t	2026-10-27 20:07:30.3217+00
185	André Oliveira	115	154	149	100	t	2026-10-27 20:07:30.3217+00
186	Juliana Oliveira	122	151	149	50	t	2026-10-27 20:07:30.3217+00
187	Felipe Oliveira	129	156	149	0	t	2026-10-27 20:07:30.3217+00
188	Beatriz Oliveira	136	153	149	60	t	2026-10-27 20:07:30.3217+00
189	Gabriel Oliveira	77	150	149	10	t	2026-10-27 20:07:30.3217+00
190	Larissa Oliveira	84	155	149	70	f	2026-10-27 20:07:30.3217+00
191	Thiago Oliveira	91	152	149	20	t	2026-10-27 20:07:30.3217+00
192	Renata Oliveira	98	157	149	80	t	2026-10-27 20:07:30.3217+00
193	Bruno Oliveira	105	154	149	30	t	2026-10-27 20:07:30.3217+00
194	Patricia Oliveira	112	151	149	90	t	2026-10-27 20:07:30.3217+00
195	Daniel Oliveira	119	156	149	40	t	2026-10-27 20:07:30.3217+00
196	Fernanda Oliveira	126	153	149	100	t	2026-10-27 20:07:30.3217+00
197	Eduardo Oliveira	133	150	149	50	t	2026-10-27 20:07:30.3217+00
198	Amanda Oliveira	140	155	149	0	t	2026-10-27 20:07:30.3217+00
199	Rodrigo Oliveira	81	152	149	60	t	2026-10-27 20:07:30.3217+00
200	Vanessa Oliveira	88	157	149	10	t	2026-10-27 20:07:30.3217+00
201	Lucas Pereira	95	154	149	70	t	2026-10-27 20:07:30.3217+00
202	Mariana Pereira	102	151	149	20	t	2026-10-27 20:07:30.3217+00
203	Rafael Pereira	109	156	149	80	t	2026-10-27 20:07:30.3217+00
204	Camila Pereira	116	153	149	30	t	2026-10-27 20:07:30.3217+00
205	André Pereira	123	150	149	90	t	2026-10-27 20:07:30.3217+00
206	Juliana Pereira	130	155	149	40	t	2026-10-27 20:07:30.3217+00
207	Felipe Pereira	137	152	149	100	t	2026-10-27 20:07:30.3217+00
208	Beatriz Pereira	78	157	149	50	t	2026-10-27 20:07:30.3217+00
209	Gabriel Pereira	85	154	149	0	f	2026-10-27 20:07:30.3217+00
210	Larissa Pereira	92	151	149	60	t	2026-10-27 20:07:30.3217+00
211	Thiago Pereira	99	156	149	10	t	2026-10-27 20:07:30.3217+00
212	Renata Pereira	106	153	149	70	t	2026-10-27 20:07:30.3217+00
213	Bruno Pereira	113	150	149	20	t	2026-10-27 20:07:30.3217+00
214	Patricia Pereira	120	155	149	80	t	2026-10-27 20:07:30.3217+00
215	Daniel Pereira	127	152	149	30	t	2026-10-27 20:07:30.3217+00
216	Fernanda Pereira	134	157	149	90	t	2026-10-27 20:07:30.3217+00
217	Eduardo Pereira	75	154	149	40	t	2026-10-27 20:07:30.3217+00
218	Amanda Pereira	82	151	149	100	t	2026-10-27 20:07:30.3217+00
219	Rodrigo Pereira	89	156	149	50	t	2026-10-27 20:07:30.3217+00
220	Vanessa Pereira	96	153	149	0	t	2026-10-27 20:07:30.3217+00
221	Lucas Ribeiro	103	150	149	60	t	2026-10-27 20:07:30.3217+00
222	Mariana Ribeiro	110	155	149	10	t	2026-10-27 20:07:30.3217+00
223	Rafael Ribeiro	117	152	149	70	t	2026-10-27 20:07:30.3217+00
224	Camila Ribeiro	124	157	149	20	t	2026-10-27 20:07:30.3217+00
225	André Ribeiro	131	154	149	80	t	2026-10-27 20:07:30.3217+00
226	Juliana Ribeiro	138	151	149	30	t	2026-10-27 20:07:30.3217+00
227	Felipe Ribeiro	79	156	149	90	t	2026-10-27 20:07:30.3217+00
228	Beatriz Ribeiro	86	153	149	40	f	2026-10-27 20:07:30.3217+00
229	Gabriel Ribeiro	93	150	149	100	t	2026-10-27 20:07:30.3217+00
230	Larissa Ribeiro	100	155	149	50	t	2026-10-27 20:07:30.3217+00
231	Thiago Ribeiro	107	152	149	0	t	2026-10-27 20:07:30.3217+00
232	Renata Ribeiro	114	157	149	60	t	2026-10-27 20:07:30.3217+00
233	Bruno Ribeiro	121	154	149	10	t	2026-10-27 20:07:30.3217+00
234	Patricia Ribeiro	128	151	149	70	t	2026-10-27 20:07:30.3217+00
235	Daniel Ribeiro	135	156	149	20	t	2026-10-27 20:07:30.3217+00
236	Fernanda Ribeiro	76	153	149	80	t	2026-10-27 20:07:30.3217+00
237	Eduardo Ribeiro	83	150	149	30	t	2026-10-27 20:07:30.3217+00
238	Amanda Ribeiro	90	155	149	90	t	2026-10-27 20:07:30.3217+00
239	Rodrigo Ribeiro	97	152	149	40	t	2026-10-27 20:07:30.3217+00
240	Vanessa Ribeiro	104	157	149	100	t	2026-10-27 20:07:30.3217+00
241	Lucas Rocha	111	154	149	50	t	2026-10-27 20:07:30.3217+00
242	Mariana Rocha	118	151	149	0	t	2026-10-27 20:07:30.3217+00
243	Rafael Rocha	125	156	149	60	t	2026-10-27 20:07:30.3217+00
244	Camila Rocha	132	153	149	10	t	2026-10-27 20:07:30.3217+00
245	André Rocha	139	150	149	70	t	2026-10-27 20:07:30.3217+00
246	Juliana Rocha	80	155	149	20	t	2026-10-27 20:07:30.3217+00
247	Felipe Rocha	87	152	149	80	f	2026-10-27 20:07:30.3217+00
248	Beatriz Rocha	94	157	149	30	t	2026-10-27 20:07:30.3217+00
249	Gabriel Rocha	101	154	149	90	t	2026-10-27 20:07:30.3217+00
250	Larissa Rocha	108	151	149	40	t	2026-10-27 20:07:30.3217+00
251	Thiago Rocha	115	156	149	100	t	2026-10-27 20:07:30.3217+00
252	Renata Rocha	122	153	149	50	t	2026-10-27 20:07:30.3217+00
253	Bruno Rocha	129	150	149	0	t	2026-10-27 20:07:30.3217+00
254	Patricia Rocha	136	155	149	60	t	2026-10-27 20:07:30.3217+00
255	Daniel Rocha	77	152	149	10	t	2026-10-27 20:07:30.3217+00
256	Fernanda Rocha	84	157	149	70	t	2026-10-27 20:07:30.3217+00
257	Eduardo Rocha	91	154	149	20	t	2026-10-27 20:07:30.3217+00
258	Amanda Rocha	98	151	149	80	t	2026-10-27 20:07:30.3217+00
259	Rodrigo Rocha	105	156	149	30	t	2026-10-27 20:07:30.3217+00
260	Vanessa Rocha	112	153	149	90	t	2026-10-27 20:07:30.3217+00
261	Lucas Santana	119	150	149	40	t	2026-10-27 20:07:30.3217+00
262	Mariana Santana	126	155	149	100	t	2026-10-27 20:07:30.3217+00
263	Rafael Santana	133	152	149	50	t	2026-10-27 20:07:30.3217+00
264	Camila Santana	140	157	149	0	t	2026-10-27 20:07:30.3217+00
265	André Santana	81	154	149	60	t	2026-10-27 20:07:30.3217+00
266	Juliana Santana	88	151	149	10	f	2026-10-27 20:07:30.3217+00
267	Felipe Santana	95	156	149	70	t	2026-10-27 20:07:30.3217+00
268	Beatriz Santana	102	153	149	20	t	2026-10-27 20:07:30.3217+00
269	Gabriel Santana	109	150	149	80	t	2026-10-27 20:07:30.3217+00
270	Larissa Santana	116	155	149	30	t	2026-10-27 20:07:30.3217+00
271	Thiago Santana	123	152	149	90	t	2026-10-27 20:07:30.3217+00
272	Renata Santana	130	157	149	40	t	2026-10-27 20:07:30.3217+00
273	Bruno Santana	137	154	149	100	t	2026-10-27 20:07:30.3217+00
274	Patricia Santana	78	151	149	50	t	2026-10-27 20:07:30.3217+00
275	Daniel Santana	85	156	149	0	t	2026-10-27 20:07:30.3217+00
276	Fernanda Santana	92	153	149	60	t	2026-10-27 20:07:30.3217+00
277	Eduardo Santana	99	150	149	10	t	2026-10-27 20:07:30.3217+00
278	Amanda Santana	106	155	149	70	t	2026-10-27 20:07:30.3217+00
279	Rodrigo Santana	113	152	149	20	t	2026-10-27 20:07:30.3217+00
280	Vanessa Santana	120	157	149	80	t	2026-10-27 20:07:30.3217+00
281	Lucas Silva	127	154	149	30	t	2026-10-27 20:07:30.3217+00
282	Mariana Silva	134	151	149	90	t	2026-10-27 20:07:30.3217+00
283	Rafael Silva	75	156	149	40	t	2026-10-27 20:07:30.3217+00
284	Camila Silva	82	153	149	100	t	2026-10-27 20:07:30.3217+00
285	André Silva	89	150	149	50	f	2026-10-27 20:07:30.3217+00
286	Juliana Silva	96	155	149	0	t	2026-10-27 20:07:30.3217+00
287	Felipe Silva	103	152	149	60	t	2026-10-27 20:07:30.3217+00
288	Beatriz Silva	110	157	149	10	t	2026-10-27 20:07:30.3217+00
289	Gabriel Silva	117	154	149	70	t	2026-10-27 20:07:30.3217+00
290	Larissa Silva	124	151	149	20	t	2026-10-27 20:07:30.3217+00
291	Thiago Silva	131	156	149	80	t	2026-10-27 20:07:30.3217+00
292	Renata Silva	138	153	149	30	t	2026-10-27 20:07:30.3217+00
293	Bruno Silva	79	150	149	90	t	2026-10-27 20:07:30.3217+00
294	Patricia Silva	86	155	149	40	t	2026-10-27 20:07:30.3217+00
295	Daniel Silva	93	152	149	100	t	2026-10-27 20:07:30.3217+00
296	Fernanda Silva	100	157	149	50	t	2026-10-27 20:07:30.3217+00
297	Eduardo Silva	107	154	149	0	t	2026-10-27 20:07:30.3217+00
298	Amanda Silva	114	151	149	60	t	2026-10-27 20:07:30.3217+00
299	Rodrigo Silva	121	156	149	10	t	2026-10-27 20:07:30.3217+00
300	Vanessa Silva	128	153	149	70	t	2026-10-27 20:07:30.3217+00
\.


--
-- TOC entry 3658 (class 0 OID 0)
-- Dependencies: 236
-- Name: alocacoes_id_seq; Type: SEQUENCE SET; Schema: InHire; Owner: postgres
--

SELECT pg_catalog.setval('"InHire".alocacoes_id_seq', 635, true);


--
-- TOC entry 3659 (class 0 OID 0)
-- Dependencies: 232
-- Name: colaborador_skills_id_seq; Type: SEQUENCE SET; Schema: InHire; Owner: postgres
--

SELECT pg_catalog.setval('"InHire".colaborador_skills_id_seq', 12679, true);


--
-- TOC entry 3660 (class 0 OID 0)
-- Dependencies: 226
-- Name: colaboradores_id_seq; Type: SEQUENCE SET; Schema: InHire; Owner: postgres
--

SELECT pg_catalog.setval('"InHire".colaboradores_id_seq', 336, true);


--
-- TOC entry 3661 (class 0 OID 0)
-- Dependencies: 224
-- Name: contratos_id_seq; Type: SEQUENCE SET; Schema: InHire; Owner: postgres
--

SELECT pg_catalog.setval('"InHire".contratos_id_seq', 16, true);


--
-- TOC entry 3662 (class 0 OID 0)
-- Dependencies: 234
-- Name: demanda_skills_id_seq; Type: SEQUENCE SET; Schema: InHire; Owner: postgres
--

SELECT pg_catalog.setval('"InHire".demanda_skills_id_seq', 337, true);


--
-- TOC entry 3663 (class 0 OID 0)
-- Dependencies: 228
-- Name: demandas_id_seq; Type: SEQUENCE SET; Schema: InHire; Owner: postgres
--

SELECT pg_catalog.setval('"InHire".demandas_id_seq', 126, true);


--
-- TOC entry 3664 (class 0 OID 0)
-- Dependencies: 222
-- Name: dominios_id_seq; Type: SEQUENCE SET; Schema: InHire; Owner: postgres
--

SELECT pg_catalog.setval('"InHire".dominios_id_seq', 321, true);


--
-- TOC entry 3665 (class 0 OID 0)
-- Dependencies: 238
-- Name: planejamentos_id_seq; Type: SEQUENCE SET; Schema: InHire; Owner: postgres
--

SELECT pg_catalog.setval('"InHire".planejamentos_id_seq', 5039, true);


--
-- TOC entry 3666 (class 0 OID 0)
-- Dependencies: 230
-- Name: skills_id_seq; Type: SEQUENCE SET; Schema: InHire; Owner: postgres
--

SELECT pg_catalog.setval('"InHire".skills_id_seq', 159, true);


--
-- TOC entry 3667 (class 0 OID 0)
-- Dependencies: 242
-- Name: talento_skills_id_seq; Type: SEQUENCE SET; Schema: InHire; Owner: postgres
--

SELECT pg_catalog.setval('"InHire".talento_skills_id_seq', 3000, true);


--
-- TOC entry 3668 (class 0 OID 0)
-- Dependencies: 240
-- Name: talentos_id_seq; Type: SEQUENCE SET; Schema: InHire; Owner: postgres
--

SELECT pg_catalog.setval('"InHire".talentos_id_seq', 300, true);


--
-- TOC entry 3423 (class 2606 OID 95815)
-- Name: alocacoes alocacoes_pkey; Type: CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".alocacoes
    ADD CONSTRAINT alocacoes_pkey PRIMARY KEY (id);


--
-- TOC entry 3414 (class 2606 OID 95772)
-- Name: colaborador_skills colaborador_skills_pkey; Type: CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".colaborador_skills
    ADD CONSTRAINT colaborador_skills_pkey PRIMARY KEY (id);


--
-- TOC entry 3394 (class 2606 OID 95663)
-- Name: colaboradores colaboradores_pkey; Type: CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".colaboradores
    ADD CONSTRAINT colaboradores_pkey PRIMARY KEY (id);


--
-- TOC entry 3389 (class 2606 OID 95643)
-- Name: contratos contratos_pkey; Type: CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".contratos
    ADD CONSTRAINT contratos_pkey PRIMARY KEY (id);


--
-- TOC entry 3419 (class 2606 OID 95796)
-- Name: demanda_skills demanda_skills_pkey; Type: CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".demanda_skills
    ADD CONSTRAINT demanda_skills_pkey PRIMARY KEY (id);


--
-- TOC entry 3403 (class 2606 OID 95716)
-- Name: demandas demandas_pkey; Type: CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".demandas
    ADD CONSTRAINT demandas_pkey PRIMARY KEY (id);


--
-- TOC entry 3387 (class 2606 OID 95632)
-- Name: dominios dominios_pkey; Type: CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".dominios
    ADD CONSTRAINT dominios_pkey PRIMARY KEY (id);


--
-- TOC entry 3429 (class 2606 OID 95839)
-- Name: planejamentos planejamentos_id_alocacao_mes_ano_key; Type: CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".planejamentos
    ADD CONSTRAINT planejamentos_id_alocacao_mes_ano_key UNIQUE (id_alocacao, mes, ano);


--
-- TOC entry 3431 (class 2606 OID 95837)
-- Name: planejamentos planejamentos_pkey; Type: CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".planejamentos
    ADD CONSTRAINT planejamentos_pkey PRIMARY KEY (id);


--
-- TOC entry 3411 (class 2606 OID 95756)
-- Name: skills skills_pkey; Type: CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".skills
    ADD CONSTRAINT skills_pkey PRIMARY KEY (id);


--
-- TOC entry 3440 (class 2606 OID 95904)
-- Name: talento_skills talento_skills_id_talento_id_skill_key; Type: CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".talento_skills
    ADD CONSTRAINT talento_skills_id_talento_id_skill_key UNIQUE (id_talento, id_skill);


--
-- TOC entry 3442 (class 2606 OID 95902)
-- Name: talento_skills talento_skills_pkey; Type: CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".talento_skills
    ADD CONSTRAINT talento_skills_pkey PRIMARY KEY (id);


--
-- TOC entry 3436 (class 2606 OID 95880)
-- Name: talentos talentos_pkey; Type: CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".talentos
    ADD CONSTRAINT talentos_pkey PRIMARY KEY (id);


--
-- TOC entry 3424 (class 1259 OID 95868)
-- Name: ix_alocacoes_ativas; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_alocacoes_ativas ON "InHire".alocacoes USING btree (id_colaborador, id) WHERE ((status IS TRUE) AND (deletado IS FALSE));


--
-- TOC entry 3425 (class 1259 OID 95866)
-- Name: ix_alocacoes_colaborador_demanda; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_alocacoes_colaborador_demanda ON "InHire".alocacoes USING btree (id_colaborador, id_demanda);


--
-- TOC entry 3426 (class 1259 OID 95867)
-- Name: ix_alocacoes_demanda; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_alocacoes_demanda ON "InHire".alocacoes USING btree (id_demanda);


--
-- TOC entry 3395 (class 1259 OID 95848)
-- Name: ix_colaboradores_cargo; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_colaboradores_cargo ON "InHire".colaboradores USING btree (id_cargo);


--
-- TOC entry 3396 (class 1259 OID 95854)
-- Name: ix_colaboradores_contrato; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_colaboradores_contrato ON "InHire".colaboradores USING btree (id_contrato);


--
-- TOC entry 3397 (class 1259 OID 95852)
-- Name: ix_colaboradores_modalidade; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_colaboradores_modalidade ON "InHire".colaboradores USING btree (id_modalidade);


--
-- TOC entry 3398 (class 1259 OID 95849)
-- Name: ix_colaboradores_senioridade; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_colaboradores_senioridade ON "InHire".colaboradores USING btree (id_senioridade);


--
-- TOC entry 3399 (class 1259 OID 95853)
-- Name: ix_colaboradores_setor; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_colaboradores_setor ON "InHire".colaboradores USING btree (id_setor_empresa);


--
-- TOC entry 3400 (class 1259 OID 95850)
-- Name: ix_colaboradores_step; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_colaboradores_step ON "InHire".colaboradores USING btree (id_step);


--
-- TOC entry 3401 (class 1259 OID 95851)
-- Name: ix_colaboradores_vinculo; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_colaboradores_vinculo ON "InHire".colaboradores USING btree (id_vinculo);


--
-- TOC entry 3390 (class 1259 OID 95846)
-- Name: ix_contratos_centro_custo; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_contratos_centro_custo ON "InHire".contratos USING btree (id_centro_custo);


--
-- TOC entry 3391 (class 1259 OID 95847)
-- Name: ix_contratos_preposto; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_contratos_preposto ON "InHire".contratos USING btree (id_preposto);


--
-- TOC entry 3392 (class 1259 OID 95845)
-- Name: ix_contratos_situacao; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_contratos_situacao ON "InHire".contratos USING btree (id_situacao);


--
-- TOC entry 3415 (class 1259 OID 95861)
-- Name: ix_cs_colaborador_skill; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_cs_colaborador_skill ON "InHire".colaborador_skills USING btree (id_colaborador, id_skill);


--
-- TOC entry 3416 (class 1259 OID 95863)
-- Name: ix_cs_nivel; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_cs_nivel ON "InHire".colaborador_skills USING btree (id_nivel_conhecimento);


--
-- TOC entry 3417 (class 1259 OID 95862)
-- Name: ix_cs_skill; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_cs_skill ON "InHire".colaborador_skills USING btree (id_skill);


--
-- TOC entry 3404 (class 1259 OID 95859)
-- Name: ix_demandas_andamento; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_demandas_andamento ON "InHire".demandas USING btree (id_andamento_demanda);


--
-- TOC entry 3405 (class 1259 OID 95856)
-- Name: ix_demandas_contrato; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_demandas_contrato ON "InHire".demandas USING btree (id_contrato);


--
-- TOC entry 3406 (class 1259 OID 95855)
-- Name: ix_demandas_gerente; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_demandas_gerente ON "InHire".demandas USING btree (id_gerente);


--
-- TOC entry 3407 (class 1259 OID 95860)
-- Name: ix_demandas_grupo; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_demandas_grupo ON "InHire".demandas USING btree (id_grupo);


--
-- TOC entry 3408 (class 1259 OID 95858)
-- Name: ix_demandas_metodologia; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_demandas_metodologia ON "InHire".demandas USING btree (id_metodologia);


--
-- TOC entry 3409 (class 1259 OID 95857)
-- Name: ix_demandas_tipo_servico; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_demandas_tipo_servico ON "InHire".demandas USING btree (id_tipo_servico);


--
-- TOC entry 3420 (class 1259 OID 95864)
-- Name: ix_ds_demanda_skill; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_ds_demanda_skill ON "InHire".demanda_skills USING btree (id_demanda, id_skill);


--
-- TOC entry 3421 (class 1259 OID 95865)
-- Name: ix_ds_skill; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_ds_skill ON "InHire".demanda_skills USING btree (id_skill);


--
-- TOC entry 3427 (class 1259 OID 95869)
-- Name: ix_planejamentos_competencia; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_planejamentos_competencia ON "InHire".planejamentos USING btree (ano, mes, id_alocacao);


--
-- TOC entry 3432 (class 1259 OID 95920)
-- Name: ix_talentos_cargo; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_talentos_cargo ON "InHire".talentos USING btree (id_cargo);


--
-- TOC entry 3433 (class 1259 OID 95922)
-- Name: ix_talentos_modalidade; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_talentos_modalidade ON "InHire".talentos USING btree (id_modalidade);


--
-- TOC entry 3434 (class 1259 OID 95921)
-- Name: ix_talentos_senioridade; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_talentos_senioridade ON "InHire".talentos USING btree (id_senioridade);


--
-- TOC entry 3437 (class 1259 OID 95924)
-- Name: ix_ts_nivel; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_ts_nivel ON "InHire".talento_skills USING btree (id_nivel_conhecimento);


--
-- TOC entry 3438 (class 1259 OID 95923)
-- Name: ix_ts_skill; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE INDEX ix_ts_skill ON "InHire".talento_skills USING btree (id_skill);


--
-- TOC entry 3412 (class 1259 OID 95762)
-- Name: uq_skills_area_nome; Type: INDEX; Schema: InHire; Owner: postgres
--

CREATE UNIQUE INDEX uq_skills_area_nome ON "InHire".skills USING btree (id_area_tecnologia, lower(btrim((nome_skill)::text)));


--
-- TOC entry 3465 (class 2606 OID 95816)
-- Name: alocacoes alocacoes_id_colaborador_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".alocacoes
    ADD CONSTRAINT alocacoes_id_colaborador_fkey FOREIGN KEY (id_colaborador) REFERENCES "InHire".colaboradores(id) ON DELETE RESTRICT;


--
-- TOC entry 3466 (class 2606 OID 95821)
-- Name: alocacoes alocacoes_id_demanda_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".alocacoes
    ADD CONSTRAINT alocacoes_id_demanda_fkey FOREIGN KEY (id_demanda) REFERENCES "InHire".demandas(id) ON DELETE RESTRICT;


--
-- TOC entry 3460 (class 2606 OID 95773)
-- Name: colaborador_skills colaborador_skills_id_colaborador_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".colaborador_skills
    ADD CONSTRAINT colaborador_skills_id_colaborador_fkey FOREIGN KEY (id_colaborador) REFERENCES "InHire".colaboradores(id) ON DELETE RESTRICT;


--
-- TOC entry 3461 (class 2606 OID 95783)
-- Name: colaborador_skills colaborador_skills_id_nivel_conhecimento_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".colaborador_skills
    ADD CONSTRAINT colaborador_skills_id_nivel_conhecimento_fkey FOREIGN KEY (id_nivel_conhecimento) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3462 (class 2606 OID 95778)
-- Name: colaborador_skills colaborador_skills_id_skill_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".colaborador_skills
    ADD CONSTRAINT colaborador_skills_id_skill_fkey FOREIGN KEY (id_skill) REFERENCES "InHire".skills(id) ON DELETE RESTRICT;


--
-- TOC entry 3446 (class 2606 OID 95664)
-- Name: colaboradores colaboradores_id_cargo_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".colaboradores
    ADD CONSTRAINT colaboradores_id_cargo_fkey FOREIGN KEY (id_cargo) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3447 (class 2606 OID 95694)
-- Name: colaboradores colaboradores_id_contrato_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".colaboradores
    ADD CONSTRAINT colaboradores_id_contrato_fkey FOREIGN KEY (id_contrato) REFERENCES "InHire".contratos(id) DEFERRABLE INITIALLY DEFERRED;


--
-- TOC entry 3448 (class 2606 OID 95684)
-- Name: colaboradores colaboradores_id_modalidade_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".colaboradores
    ADD CONSTRAINT colaboradores_id_modalidade_fkey FOREIGN KEY (id_modalidade) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3449 (class 2606 OID 95669)
-- Name: colaboradores colaboradores_id_senioridade_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".colaboradores
    ADD CONSTRAINT colaboradores_id_senioridade_fkey FOREIGN KEY (id_senioridade) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3450 (class 2606 OID 95689)
-- Name: colaboradores colaboradores_id_setor_empresa_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".colaboradores
    ADD CONSTRAINT colaboradores_id_setor_empresa_fkey FOREIGN KEY (id_setor_empresa) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3451 (class 2606 OID 95674)
-- Name: colaboradores colaboradores_id_step_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".colaboradores
    ADD CONSTRAINT colaboradores_id_step_fkey FOREIGN KEY (id_step) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3452 (class 2606 OID 95679)
-- Name: colaboradores colaboradores_id_vinculo_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".colaboradores
    ADD CONSTRAINT colaboradores_id_vinculo_fkey FOREIGN KEY (id_vinculo) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3443 (class 2606 OID 95649)
-- Name: contratos contratos_id_centro_custo_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".contratos
    ADD CONSTRAINT contratos_id_centro_custo_fkey FOREIGN KEY (id_centro_custo) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3444 (class 2606 OID 95644)
-- Name: contratos contratos_id_situacao_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".contratos
    ADD CONSTRAINT contratos_id_situacao_fkey FOREIGN KEY (id_situacao) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3463 (class 2606 OID 95797)
-- Name: demanda_skills demanda_skills_id_demanda_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".demanda_skills
    ADD CONSTRAINT demanda_skills_id_demanda_fkey FOREIGN KEY (id_demanda) REFERENCES "InHire".demandas(id) ON DELETE RESTRICT;


--
-- TOC entry 3464 (class 2606 OID 95802)
-- Name: demanda_skills demanda_skills_id_skill_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".demanda_skills
    ADD CONSTRAINT demanda_skills_id_skill_fkey FOREIGN KEY (id_skill) REFERENCES "InHire".skills(id) ON DELETE RESTRICT;


--
-- TOC entry 3453 (class 2606 OID 95737)
-- Name: demandas demandas_id_andamento_demanda_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".demandas
    ADD CONSTRAINT demandas_id_andamento_demanda_fkey FOREIGN KEY (id_andamento_demanda) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3454 (class 2606 OID 95722)
-- Name: demandas demandas_id_contrato_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".demandas
    ADD CONSTRAINT demandas_id_contrato_fkey FOREIGN KEY (id_contrato) REFERENCES "InHire".contratos(id) ON DELETE RESTRICT;


--
-- TOC entry 3455 (class 2606 OID 95717)
-- Name: demandas demandas_id_gerente_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".demandas
    ADD CONSTRAINT demandas_id_gerente_fkey FOREIGN KEY (id_gerente) REFERENCES "InHire".colaboradores(id) ON DELETE RESTRICT;


--
-- TOC entry 3456 (class 2606 OID 95742)
-- Name: demandas demandas_id_grupo_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".demandas
    ADD CONSTRAINT demandas_id_grupo_fkey FOREIGN KEY (id_grupo) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3457 (class 2606 OID 95732)
-- Name: demandas demandas_id_metodologia_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".demandas
    ADD CONSTRAINT demandas_id_metodologia_fkey FOREIGN KEY (id_metodologia) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3458 (class 2606 OID 95727)
-- Name: demandas demandas_id_tipo_servico_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".demandas
    ADD CONSTRAINT demandas_id_tipo_servico_fkey FOREIGN KEY (id_tipo_servico) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3445 (class 2606 OID 95699)
-- Name: contratos fk_contratos_preposto; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".contratos
    ADD CONSTRAINT fk_contratos_preposto FOREIGN KEY (id_preposto) REFERENCES "InHire".colaboradores(id) DEFERRABLE INITIALLY DEFERRED;


--
-- TOC entry 3467 (class 2606 OID 95840)
-- Name: planejamentos planejamentos_id_alocacao_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".planejamentos
    ADD CONSTRAINT planejamentos_id_alocacao_fkey FOREIGN KEY (id_alocacao) REFERENCES "InHire".alocacoes(id) ON DELETE RESTRICT;


--
-- TOC entry 3459 (class 2606 OID 95757)
-- Name: skills skills_id_area_tecnologia_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".skills
    ADD CONSTRAINT skills_id_area_tecnologia_fkey FOREIGN KEY (id_area_tecnologia) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3471 (class 2606 OID 95915)
-- Name: talento_skills talento_skills_id_nivel_conhecimento_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".talento_skills
    ADD CONSTRAINT talento_skills_id_nivel_conhecimento_fkey FOREIGN KEY (id_nivel_conhecimento) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3472 (class 2606 OID 95910)
-- Name: talento_skills talento_skills_id_skill_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".talento_skills
    ADD CONSTRAINT talento_skills_id_skill_fkey FOREIGN KEY (id_skill) REFERENCES "InHire".skills(id) ON DELETE RESTRICT;


--
-- TOC entry 3473 (class 2606 OID 95905)
-- Name: talento_skills talento_skills_id_talento_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".talento_skills
    ADD CONSTRAINT talento_skills_id_talento_fkey FOREIGN KEY (id_talento) REFERENCES "InHire".talentos(id) ON DELETE CASCADE;


--
-- TOC entry 3468 (class 2606 OID 95881)
-- Name: talentos talentos_id_cargo_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".talentos
    ADD CONSTRAINT talentos_id_cargo_fkey FOREIGN KEY (id_cargo) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3469 (class 2606 OID 95891)
-- Name: talentos talentos_id_modalidade_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".talentos
    ADD CONSTRAINT talentos_id_modalidade_fkey FOREIGN KEY (id_modalidade) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


--
-- TOC entry 3470 (class 2606 OID 95886)
-- Name: talentos talentos_id_senioridade_fkey; Type: FK CONSTRAINT; Schema: InHire; Owner: postgres
--

ALTER TABLE ONLY "InHire".talentos
    ADD CONSTRAINT talentos_id_senioridade_fkey FOREIGN KEY (id_senioridade) REFERENCES "InHire".dominios(id) ON DELETE RESTRICT;


-- Completed on 2026-10-27 17:33:33

--
-- PostgreSQL database dump complete
--

\unrestrict a1EvXQZZhgkzsd27MbOpm1DIYAwnmThqfm1bhvWgpQKTuRRC1T9iqjtyMeff3Zw

