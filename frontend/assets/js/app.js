    // CONFIGURAÇÃO DOS ENDPOINTS DO N8N
    const N8N_BASE_URL = "http://localhost:5678/webhook";
    const ENDPOINTS = {
      BUSCA: `${N8N_BASE_URL}/d487a45d-f399-488d-a16e-0f0b6ed9bf25`,
      DASHBOARD: `${N8N_BASE_URL}/dashboard-dados`,
      DEMANDAS: `${N8N_BASE_URL}/demandas-pessoas`,
      SALVAR_FAV: `${N8N_BASE_URL}/salvar-favorito`,
      LISTAR_FAV: `${N8N_BASE_URL}/listar-favoritos`,
      REMANEJAR: `${N8N_BASE_URL}/remanejar-alocacao`,
      ALOCAR: `${N8N_BASE_URL}/alocar-profissional` 
    };

    const MAX_COMPARACAO = 4;
    const MESES = ['Jan', 'Fev', 'Mar', 'Abr', 'Mai', 'Jun', 'Jul', 'Ago', 'Set', 'Out', 'Nov', 'Dez'];
    const ABAS = ['chat', 'dashboard', 'demandas', 'comparar', 'favoritos'];

    let ultimoRanking = [];
    let selecionadosComparacao = [];
    let ultimaBuscaFeita = false;
    let buscando = false;

    let dashPessoas = null;            
    let dashVisiveis = [];             
    let demandasCache = null;
    let favoritosCache = null;
    let favoritosVisiveis = [];
    let candidatoRem = null;
    let remEnviando = false;
    let remTentou = false;
    const remToques = new Set();
    let confirmResolve = null;

    // ==========================================
    // UTILITÁRIOS
    // ==========================================
    const $ = id => document.getElementById(id);
    const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const num = (v, def = null) => { const n = parseInt(v, 10); return Number.isNaN(n) ? def : n; };
    const clamp = n => Math.max(0, Math.min(100, n));
    const icon = (n, extra = '') => `<svg class="i ${extra}" aria-hidden="true"><use href="#i-${n}"/></svg>`;
    const lista = v => Array.isArray(v) ? v : (v && typeof v === 'object' && Object.keys(v).length ? [v] : []);
    const listaTexto = v => Array.isArray(v) ? v.map(String).filter(Boolean)
      : (typeof v === 'string' && v.trim() ? v.split(/[,;]/).map(s => s.trim()).filter(Boolean) : []);
    const candKey = c => String(c.id ?? c.nome);
    const iniciais = nome => String(nome || '?').trim().split(/\s+/).slice(0, 2).map(p => p[0]).join('').toUpperCase() || '?';
    const hue = nome => { let h = 0; for (const ch of String(nome || '')) h = (h * 31 + ch.charCodeAt(0)) % 360; return h; };
    const avatar = (nome, sm = false) => `<span class="avatar ${sm ? 'sm' : ''}" style="--h:${hue(nome)}" aria-hidden="true">${esc(iniciais(nome))}</span>`;
    const fmtData = v => { const s = String(v ?? ''); const m = s.match(/^(\d{4})-(\d{2})-(\d{2})/); return m ? `${m[3]}/${m[2]}/${m[1]}` : (s || '—'); };
    const tipoInterno = c => c.tipo_base === 'interno' || /interno|sgd/i.test(String(c.origem || ''));
    const precisaRemanejar = c => tipoInterno(c) && String(c.status_acao || '').toLowerCase().includes('remanejamento');

    function bar(n, cls) {
      if (n === null) return '';
      return `<div class="bar" aria-hidden="true"><i class="${cls}" style="width:${clamp(n)}%"></i></div>`;
    }
    const clsDisp = n => n === null ? 'err' : n >= 100 ? 'ok' : n > 0 ? 'warn' : 'err';

    async function requisitar(url, opcoes) {
      const res = await fetch(url, opcoes);
      const texto = await res.text();
      let dados = null;
      if (texto) { try { dados = JSON.parse(texto); } catch { dados = null; } }
      if (!res.ok) { const e = new Error(`HTTP ${res.status}`); e.status = res.status; e.dados = dados; throw e; }
      return dados;
    }
    function msgErro(e) {
      if (e instanceof TypeError) return 'Não foi possível conectar. Verifique o servidor local/n8n.';
      if (e && e.status) return `O servidor respondeu com erro (HTTP ${e.status}).`;
      return (e && e.message) || 'Erro inesperado.';
    }

    function setLoading(btn, on, rotulo) {
      if (!btn) return;
      const lbl = btn.querySelector('.btn-label');
      if (on) {
        if (lbl) { btn.dataset.label = lbl.textContent; if (rotulo) lbl.textContent = rotulo; }
        btn.classList.add('is-loading'); btn.disabled = true; btn.setAttribute('aria-busy', 'true');
        const sp = document.createElement('span'); sp.className = 'spin'; sp.dataset.spin = '1';
        btn.prepend(sp);
      } else {
        btn.querySelector('[data-spin]')?.remove();
        if (lbl && btn.dataset.label) lbl.textContent = btn.dataset.label;
        btn.classList.remove('is-loading'); btn.disabled = false; btn.removeAttribute('aria-busy');
      }
    }

    function estado({ icone = 'info', titulo, texto, extra = '', erro = false, compacto = false }) {
      return `<div class="state ${erro ? 'err' : ''} ${compacto ? 'compact' : ''}">
        <span class="s-ico">${icon(icone, 'i-lg')}</span>
        <h3>${esc(titulo)}</h3>${texto ? `<p>${esc(texto)}</p>` : ''}${extra}
      </div>`;
    }

    // ==========================================
    // TOASTS
    // ==========================================
    function toast(msg, { tipo = 'info', titulo = '', duracao = 5500 } = {}) {
      const ico = { success: 'check', error: 'alert', warn: 'alert', info: 'info' }[tipo];
      const el = document.createElement('div');
      el.className = `toast ${tipo}`;
      el.setAttribute('role', tipo === 'error' ? 'alert' : 'status');
      el.innerHTML = `<span class="t-ico">${icon(ico)}</span>
        <div>${titulo ? `<b>${esc(titulo)}</b>` : ''}<p>${esc(msg)}</p></div>
        <button type="button" class="t-x" aria-label="Fechar notificação">${icon('x')}</button>`;
      const fechar = () => { el.classList.add('out'); setTimeout(() => el.remove(), 200); };
      el.querySelector('.t-x').addEventListener('click', fechar);
      $('toasts').appendChild(el);
      while ($('toasts').children.length > 4) $('toasts').firstChild.remove();
      if (duracao) setTimeout(fechar, duracao);
    }

    // ==========================================
    // MODAIS E PERFIL DETALHADO (GLOBAL)
    // ==========================================
    const focoAnterior = {};
    function abrirModal(id, focoId) {
      const m = $(id);
      focoAnterior[id] = document.activeElement;
      m.classList.remove('hidden');
      setTimeout(() => {
        const alvo = (focoId && $(focoId)) || m.querySelector('input:not([type=hidden]),select,textarea,button:not(.icon-btn)');
        alvo && alvo.focus();
      }, 30);
    }
    function fecharModal(id) {
      if (id === 'modal-remanejar' && remEnviando) return;
      $(id).classList.add('hidden');
      if (id === 'modal-confirm' && confirmResolve) { const r = confirmResolve; confirmResolve = null; r(false); }
      const f = focoAnterior[id];
      if (f && document.body.contains(f)) f.focus();
    }
    function confirmar({ titulo, mensagem, ok = 'Confirmar', perigo = true }) {
      $('confirm-titulo').textContent = titulo;
      $('confirm-msg').textContent = mensagem;
      const b = $('confirm-ok'); b.textContent = ok;
      b.className = `btn ${perigo ? 'btn-danger' : 'btn-primary'}`;
      return new Promise(res => { confirmResolve = res; abrirModal('modal-confirm', 'confirm-ok'); });
    }
    function resolverConfirm(v) {
      const r = confirmResolve; confirmResolve = null;
      $('modal-confirm').classList.add('hidden');
      const f = focoAnterior['modal-confirm']; if (f && document.body.contains(f)) f.focus();
      r && r(v);
    }
    document.addEventListener('keydown', e => {
      const abertos = [...document.querySelectorAll('[data-modal]:not(.hidden)')];
      if (!abertos.length) return;
      const topo = abertos[abertos.length - 1];
      if (e.key === 'Escape') { e.preventDefault(); topo.id === 'modal-confirm' ? resolverConfirm(false) : fecharModal(topo.id); return; }
      if (e.key === 'Tab') {
        const foc = [...topo.querySelectorAll('button:not(:disabled),input:not([type=hidden]):not(:disabled),select:not(:disabled),textarea:not(:disabled),[href]')].filter(x => x.offsetParent !== null);
        if (!foc.length) return;
        const p = foc[0], u = foc[foc.length - 1];
        if (e.shiftKey && document.activeElement === p) { e.preventDefault(); u.focus(); }
        else if (!e.shiftKey && document.activeElement === u) { e.preventDefault(); p.focus(); }
      }
    });
    document.querySelectorAll('[data-modal]').forEach(m => m.addEventListener('mousedown', e => {
      if (e.target === m) m.id === 'modal-confirm' ? resolverConfirm(false) : fecharModal(m.id);
    }));

    /* Abertura e Montagem do Perfil Detalhado Universal */
    function abrirDetalhesProfissional(prof) {
      const nome = prof.nome ?? prof.nome_profissional ?? prof.nome_abreviado ?? 'Não informado';
      const id = prof.id ?? prof.id_profissional ?? prof.id_colaborador ?? prof.id_talento ?? 'Não informado';
      const cargo = prof.cargo ?? 'Não informado';
      const senioridade = prof.senioridade ?? 'Não informada';
      const origem = prof.origem ?? prof.tipo_base ?? (prof.id_colaborador ? 'Interno' : (prof.id_talento ? 'Externo' : 'Não informada'));
      const isInterno = /interno|sgd/i.test(origem);

      const skillsAll = listaTexto(prof.skills || prof.skills_cadastradas || prof.skills_buscadas_atendidas || []);
      const skillsMatch = new Set(listaTexto(prof.skills_atendidas || []));
      if (skillsAll.length === 0 && skillsMatch.size > 0) { skillsMatch.forEach(s => skillsAll.push(s)); }

      const tempoLivre = num(prof.tempo_livre ?? prof.disponibilidade ?? prof.disponibilidade_media, null);
      const alocAtual = prof.alocacao_atual ?? prof.percentual_alocado_medio ?? (tempoLivre !== null ? (100 - tempoLivre) + '%' : 'Não informado');

      const demandas = lista(prof.projetos_atuais ?? prof.demandas_atuais ?? []);

      const chavesUsadas = new Set(['nome', 'nome_profissional', 'nome_abreviado', 'id', 'id_profissional', 'id_colaborador', 'id_talento', 'cargo', 'senioridade', 'origem', 'tipo_base', 'skills', 'skills_cadastradas', 'skills_buscadas_atendidas', 'skills_atendidas', 'tempo_livre', 'disponibilidade', 'disponibilidade_media', 'alocacao_atual', 'percentual_alocado_medio', 'projetos_atuais', 'demandas_atuais', 'posicao', 'status_acao', 'aderencia_skills', 'score_ranking', 'qtd_skills_atendidas', 'qtd_skills_pedidas', 'match_encontrado']);
      let extraHtml = '';
      for (const [k, v] of Object.entries(prof)) {
        if (!chavesUsadas.has(k) && v !== null && v !== undefined && v !== '') {
          const rot = k.replace(/_/g, ' ').replace(/^./, c => c.toUpperCase());
          const val = typeof v === 'object' ? JSON.stringify(v) : v;
          extraHtml += `<div><dt style="font-size:12px;font-weight:600;letter-spacing:.06em;text-transform:uppercase;color:var(--faint);padding-bottom:4px">${esc(rot)}</dt><dd style="margin:0;font-size:14px;color:var(--text)">${esc(val)}</dd></div>`;
        }
      }

      $('det-titulo').textContent = nome;
      $('det-sub').textContent = `${cargo} • ${senioridade}`;
      $('det-avatar').style.setProperty('--h', hue(nome));
      $('det-avatar').textContent = iniciais(nome);

      const styleBlock = `background:rgba(255,255,255,.02); padding:16px; border-radius:12px; border:1px solid var(--line);`;
      const s1 = `<div><h4 class="eyebrow" style="color:var(--blue);margin-bottom:10px">1. Identificação</h4>
        <div style="display:grid; grid-template-columns:1fr 1fr; gap:16px; ${styleBlock}">
          <div><span style="font-size:12px;color:var(--faint)">ID / Matrícula</span><br><b style="font-size:15px">${esc(id)}</b></div>
          <div><span style="font-size:12px;color:var(--faint)">Origem</span><br><span class="badge ${isInterno?'int':'ext'}">${esc(origem)}</span></div>
          <div><span style="font-size:12px;color:var(--faint)">Cargo</span><br><b style="font-size:15px">${esc(cargo)}</b></div>
          <div><span style="font-size:12px;color:var(--faint)">Senioridade</span><br><b style="font-size:15px">${esc(senioridade)}</b></div>
        </div></div>`;

      const s2 = `<div><h4 class="eyebrow" style="color:var(--blue);margin-bottom:10px">2. Competências (Skills)</h4>
        <div style="${styleBlock}">
          ${skillsAll.length ? `<div class="tags">${skillsAll.map(s => `<span class="tag ${skillsMatch.has(s) ? 'brand' : ''}">${esc(s)}</span>`).join('')}</div>` : '<p style="font-size:14px;color:var(--muted);margin:0">Nenhuma competência cadastrada para este perfil.</p>'}
        </div></div>`;

      const s3 = `<div><h4 class="eyebrow" style="color:var(--blue);margin-bottom:10px">3. Disponibilidade (Agenda)</h4>
        <div style="display:grid; grid-template-columns:1fr 1fr; gap:16px; ${styleBlock}">
          <div><span style="font-size:12px;color:var(--faint)">Tempo Livre</span><br><b style="font-size:18px; color:${tempoLivre === 100 ? '#6ee7b7' : (tempoLivre > 0 ? '#fcd34d' : '#fda4af')}">${tempoLivre !== null ? tempoLivre + '%' : '—'}</b></div>
          <div><span style="font-size:12px;color:var(--faint)">Total Alocado</span><br><b style="font-size:18px">${esc(alocAtual)}</b></div>
          <div style="grid-column:1/-1;">${bar(tempoLivre, clsDisp(tempoLivre))}</div>
        </div></div>`;

      const s4 = `<div><h4 class="eyebrow" style="color:var(--blue);margin-bottom:10px">4. Alocações Atuais (Demandas)</h4>
        <div style="${styleBlock} display:grid; gap:10px;">
          ${demandas.length ? demandas.map(d => `<div style="font-size:14px; display:flex; justify-content:space-between; align-items:center; border-bottom:1px solid var(--line-2); padding-bottom:8px">
            <span><b>${esc(d.nome_demanda ?? d.nome ?? 'Projeto Omitido')}</b> <span style="color:var(--faint);font-size:12px">(ID ${esc(d.id_demanda ?? '—')})</span></span>
            <span class="count-pill" style="font-size:12px;padding:3px 8px">${esc(d.percentual_na_demanda ?? d.porcentagem ?? '—')}%</span>
          </div>`).join('') : '<p style="font-size:14px;color:var(--muted);margin:0">Nenhuma alocação ativa neste período.</p>'}
        </div></div>`;

      const s5 = extraHtml ? `<div><h4 class="eyebrow" style="color:var(--blue);margin-bottom:10px">5. Informações Adicionais</h4>
        <div style="${styleBlock} display:grid; gap:12px; grid-template-columns:1fr 1fr;">${extraHtml}</div></div>` : '';

      $('det-corpo').innerHTML = s1 + s2 + s3 + s4 + s5;
      abrirModal('modal-detalhes');
    }

    // ==========================================
    // SIDEBAR (recolher / drawer)
    // ==========================================
    const app = $('app');
    const mqMobile = window.matchMedia('(max-width: 900px)');
    function sidebarAberta() { return mqMobile.matches ? app.classList.contains('sb-open') : !app.classList.contains('sb-collapsed'); }
    function definirSidebar(aberta) {
      if (mqMobile.matches) app.classList.toggle('sb-open', aberta);
      else { app.classList.toggle('sb-collapsed', !aberta); try { localStorage.setItem('inhire_sb_aberta', aberta ? '1' : '0'); } catch (e) {} }
      const b = $('btn-sb-collapse');
      if (!b) return;
      b.setAttribute('aria-expanded', String(aberta));
      const rot = mqMobile.matches ? 'Fechar painel de busca' : (aberta ? 'Recolher painel de busca' : 'Expandir painel de busca');
      b.setAttribute('aria-label', rot); b.title = rot;
    }
    function focarBusca() { definirSidebar(true); setTimeout(() => $('input-ia').focus(), 260); }
    function definirTelaCheia(ligar) {
      if (mqMobile.matches) return;
      if (ligar) app.classList.remove('sb-collapsed');
      app.classList.toggle('sb-full', ligar);
      const b = $('btn-sb-full');
      if (!b) return;
      const rot = ligar ? 'Sair da tela cheia' : 'Chat em tela cheia';
      b.setAttribute('aria-pressed', String(ligar));
      b.setAttribute('aria-label', rot);
      b.title = ligar ? 'Sair da tela cheia (Esc)' : 'Chat em tela cheia (Esc para sair)';
      if (ligar) setTimeout(() => $('input-ia').focus(), 50);
    }
    document.addEventListener('keydown', e => {
      if (e.key === 'Escape' && app.classList.contains('sb-full') && !document.querySelector('[data-modal]:not(.hidden)')) definirTelaCheia(false);
    });
    mqMobile.addEventListener('change', () => { app.classList.remove('sb-open'); definirTelaCheia(false); initSidebar(); });
    function initSidebar() {
      if (mqMobile.matches) { app.classList.remove('sb-collapsed'); definirSidebar(false); return; }
      let aberta = true; try { aberta = localStorage.getItem('inhire_sb_aberta') !== '0'; } catch (e) {}
      definirSidebar(aberta);
    }

    const DICA_MODO = {
      faixa_ate: 'Mostra quem tem a disponibilidade pedida e também quem está ocupado e pode ser remanejado.',
      estrito_0_a_x: 'Mostra apenas profissionais já ocupados (entre 0% e X% livres), úteis para remanejar.',
      minimo: 'Mostra apenas profissionais com pelo menos X% livres, prontos para alocação direta.'
    };
    function atualizarDicaModo() { $('modo-hint').textContent = DICA_MODO[$('modo-disp').value] || ''; }

    // ==========================================
    // 1. BUSCA INTELIGENTE E RANKING
    // ==========================================
    function skeletonRanking() {
      $('lista-ranking').innerHTML = [1, 2, 3].map(() => `<div class="sk-card" style="margin-bottom:12px">
        <div class="sk" style="height:18px;width:60%"></div><div class="sk" style="height:12px;width:40%"></div>
        <div class="sk" style="height:34px"></div><div class="sk" style="height:34px"></div></div>`).join('');
    }

    async function executarBusca() {
      if (buscando) return;
      const texto = $('input-ia').value;
      const modoDisp = $('modo-disp').value;
      const btn = $('btn-buscar');
      buscando = true; setLoading(btn, true, 'Buscando…');
      skeletonRanking();
      try {
        let data = await requisitar(ENDPOINTS.BUSCA, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ texto_busca: texto, modo_disponibilidade: modoDisp })
        });
        if (Array.isArray(data)) data = data[0];
        ultimaBuscaFeita = true;
        renderizarResultadoBusca(data || {});
        const n = ultimoRanking.length;
        toast(n ? `${n} ${n === 1 ? 'talento encontrado' : 'talentos encontrados'}.` : 'Nenhum talento encontrado para esta busca.', { tipo: n ? 'success' : 'info' });
      } catch (err) {
        console.error(err);
        $('lista-ranking').innerHTML = estado({
          icone: 'alert', erro: true, compacto: true, titulo: 'Não foi possível buscar', texto: msgErro(err),
          extra: `<button type="button" class="btn btn-ghost btn-sm" data-action="buscar">${icon('refresh')}<span>Tentar novamente</span></button>`
        });
        toast(msgErro(err), { tipo: 'error', titulo: 'Erro na busca' });
      } finally {
        buscando = false; setLoading(btn, false);
      }
    }

    function cardCandidato(cand, i) {
      const rem = precisaRemanejar(cand);
      const ader = num(cand.aderencia_skills);
      const livre = num(cand.tempo_livre);
      const emComp = selecionadosComparacao.some(s => candKey(s) === candKey(cand));
      const skills = listaTexto(cand.skills_atendidas);
      const btnPrincipal = rem
        ? `<button type="button" class="btn btn-warn btn-sm btn-main" data-action="acao-principal" data-i="${i}">${icon('swap')}<span>Remanejar alocação</span></button>`
        : `<button type="button" class="btn btn-ok btn-sm btn-main" data-action="acao-principal" data-i="${i}">${icon('plus')}<span>Adicionar ao projeto</span></button>`;
      
      return `<article class="cand" data-action="ver-perfil" data-ctx="busca" data-i="${i}">
        <div class="cand-top">
          <span class="rank" title="Posição no ranking">${esc(cand.posicao ?? i + 1)}</span>
          <div class="cand-info">
            <h4 class="cand-name" style="margin:0">${esc(cand.nome)}</h4>
            <p class="cand-meta">${esc(cand.cargo)} • ${esc(cand.senioridade)}</p>
            <div class="badges">
              <span class="badge ${tipoInterno(cand) ? 'int' : 'ext'}">${tipoInterno(cand) ? 'Interno (SGD)' : 'Externo'}</span>
              <span class="badge ${rem ? 'warn' : 'ok'}">${rem ? 'Requer remanejamento' : 'Alocação direta'}</span>
            </div>
          </div>
        </div>
        <div class="metrics">
          <div class="metric">
            <div class="metric-h"><span>Aderência às skills</span><b>${esc(cand.aderencia_skills ?? '—')}</b></div>
            ${bar(ader, 'brand')}
          </div>
          <div class="metric">
            <div class="metric-h"><span>Tempo livre</span><b>${esc(cand.tempo_livre ?? '—')}</b></div>
            ${bar(livre, clsDisp(livre))}
            <small>Alocação atual: ${esc(cand.alocacao_atual ?? '—')}</small>
          </div>
        </div>
        ${skills.length ? `<div><p class="skills-l">Skills atendidas</p><div class="tags">${skills.map(s => `<span class="tag brand">${esc(s)}</span>`).join('')}</div></div>` : ''}
        <div class="actions">
          ${btnPrincipal}
          <button type="button" class="btn btn-ghost btn-sm" data-action="favoritar" data-i="${i}" title="Salvar nos favoritos">${icon('star')}<span>Favoritar</span></button>
          <button type="button" class="btn btn-ghost btn-sm" data-action="comparar" data-i="${i}" data-key="${esc(candKey(cand))}" aria-pressed="${emComp}" title="Adicionar à comparação">${icon('columns')}<span>Comparar</span></button>
        </div>
      </article>`;
    }

    function renderizarResultadoBusca(data) {
      const resumo = data.resumo_busca || {};
      ultimoRanking = lista(data.ranking);

      $('kpi-total').innerText = resumo.total_encontrados ?? 0;

      const f = resumo.filtros_extraidos || {};
      const skillsF = listaTexto(f.skills);
      $('box-filtros-ia').innerHTML = `
        <p class="ttl">${icon('sparkles', '" style="width:14px;height:14px')}Filtros identificados pela IA</p>
        <div class="f-row"><span>Senioridade</span><span class="tag brand">${esc(f.senioridade || 'Todas')}</span></div>
        <div class="f-row"><span>Skills</span>${skillsF.length ? skillsF.map(s => `<span class="tag brand">${esc(s)}</span>`).join('') : '<span class="tag">Nenhuma identificada</span>'}</div>
        <div class="f-row"><span>Livre (mínimo)</span><span class="tag brand">${esc(f.disponibilidade_minima ?? 50)}%</span></div>`;

      const container = $('lista-ranking');
      if (ultimoRanking.length === 0) {
        container.innerHTML = estado({ icone: 'search', compacto: true, titulo: 'Nenhum talento encontrado', texto: 'Tente reduzir a disponibilidade mínima, remover uma skill ou usar o modo flexível.' });
        return;
      }

      const internos = [], externos = [];
      ultimoRanking.forEach((c, i) => (tipoInterno(c) ? internos : externos).push(cardCandidato(c, i)));
      const grupo = (rotulo, cls, itens) => itens.length ? `<section class="grp" style="margin-bottom:18px">
        <h3 class="grp-h"><span class="dot ${cls}"></span>${rotulo}<span class="count">${itens.length}</span></h3>${itens.join('')}</section>` : '';
      container.innerHTML = grupo('Profissionais internos', 'int', internos) + grupo('Profissionais externos', 'ext', externos);
    }

    // ==========================================
    // 6. NOVA ALOCAÇÃO EFETIVA
    // ==========================================
    function abrirModalAlocacaoCand(cand) {
      const livreAtual = num(cand.tempo_livre ?? cand.disponibilidade ?? cand.disponibilidade_media ?? 0);
      if (livreAtual <= 0) {
        toast(`Profissional sem disponibilidade livre. Iniciando fluxo de remanejamento.`, { tipo: 'warn' });
        abrirModalRemanejarCand(cand);
        return;
      }
      candidatoRem = cand;
      $('aloc-id-colab').value = cand.id ?? cand.id_colaborador ?? cand.id_talento;
      $('aloc-disp-atual').value = livreAtual;
      $('aloc-nome').textContent = cand.nome;
      $('aloc-avatar').textContent = iniciais(cand.nome);
      $('aloc-avatar').style.setProperty('--h', hue(cand.nome));
      $('aloc-disp').textContent = `${livreAtual}%`;
      $('aloc-pct').value = Math.min(livreAtual, 50);
      
      popularSelectDemandasAlocacao();
      previewDisponibilidade();
      $('aloc-erro-geral').innerHTML = '';
      mudarAbaAlocacao('existente');
      abrirModal('modal-alocar', 'aloc-pct');
    }

    function alocarDiretoCand(cand) { abrirModalAlocacaoCand(cand); }
    function alocarDireto(index) { alocarDiretoCand(ultimoRanking[index] || dashVisiveis[index]); }

    function mudarAbaAlocacao(tipo) {
      $('aloc-tipo').value = tipo;
      $('tab-aloc-existente').classList.toggle('active', tipo === 'existente');
      $('tab-aloc-nova').classList.toggle('active', tipo === 'nova');
      $('view-aloc-existente').classList.toggle('hidden', tipo === 'nova');
      $('view-aloc-nova').classList.toggle('hidden', tipo === 'existente');
    }

    function previewDisponibilidade() {
      const dispAtual = Number($('aloc-disp-atual').value);
      const digitado = Number($('aloc-pct').value);
      const btn = $('btn-confirmar-aloc');
      const preview = $('aloc-preview');

      if (digitado <= 0 || digitado > 100) {
        preview.textContent = "Inválido"; preview.style.color = '#fb7185';
        btn.disabled = true;
      } else if (digitado > dispAtual) {
        preview.textContent = "Ultrapassa limite"; preview.style.color = '#fb7185';
        btn.disabled = true;
      } else {
        const restante = dispAtual - digitado;
        preview.textContent = `${restante}% restantes`;
        preview.style.color = restante === 0 ? '#fcd34d' : '#6ee7b7';
        btn.disabled = false;
      }
    }

    async function popularSelectDemandasAlocacao() {
      const sel = $('aloc-demanda-select');
      const montar = () => {
        sel.innerHTML = '<option value="">-- Escolha a Demanda --</option>' + 
          (demandasCache || []).map(d => `<option value="${esc(d.id)}">${esc(d.nome)} (ID: ${esc(d.id)})</option>`).join('');
      };
      if (demandasCache) return montar();
      try {
        const t = await (await fetch(ENDPOINTS.DEMANDAS)).text();
        demandasCache = lista(t ? JSON.parse(t) : []);
        montar();
      } catch (e) { sel.innerHTML = '<option value="">Falha ao listar demandas</option>'; }
    }

    async function efetivarAlocacao() {
      const tipo = $('aloc-tipo').value;
      const pct = Number($('aloc-pct').value);
      const dispAtual = Number($('aloc-disp-atual').value);
      
      const payload = {
        id_colaborador: $('aloc-id-colab').value,
        percentual: pct,
        mes: MESES[new Date().getMonth()],
        ano: new Date().getFullYear()
      };

      if (pct <= 0 || pct > dispAtual) {
        toast("Percentual inválido ou indisponível.", { tipo: 'warn' }); return;
      }

      if (tipo === 'existente') {
        payload.id_demanda = $('aloc-demanda-select').value;
        if (!payload.id_demanda) { $('err-aloc-demanda-select').textContent = "Selecione a demanda."; return; }
        else $('err-aloc-demanda-select').textContent = "";
      } else {
        payload.nova_demanda_nome = $('aloc-nova-nome').value.trim();
        payload.nova_demanda_inicio = $('aloc-nova-inicio').value;
        payload.nova_demanda_fim = $('aloc-nova-fim').value;
        
        let erro = false;
        if (!payload.nova_demanda_nome) { $('err-aloc-nova-nome').textContent = "Nome obrigatório."; erro = true; } else $('err-aloc-nova-nome').textContent = "";
        if (!payload.nova_demanda_inicio) { $('err-aloc-nova-inicio').textContent = "Início obrigatório."; erro = true; } else $('err-aloc-nova-inicio').textContent = "";
        if (payload.nova_demanda_fim && new Date(payload.nova_demanda_fim) < new Date(payload.nova_demanda_inicio)) {
          $('aloc-erro-geral').innerHTML = `<span>Término não pode ser anterior ao início.</span>`; erro = true;
        }
        if (erro) return;
      }

      const btn = $('btn-confirmar-aloc');
      setLoading(btn, true, 'Registrando...');
      $('aloc-erro-geral').innerHTML = '';

      try {
        await requisitar(ENDPOINTS.ALOCAR, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });
        
        fecharModal('modal-alocar');
        toast(`Profissional alocado com sucesso! Disponibilidade restante: ${dispAtual - pct}%.`, { tipo: 'success', duracao: 6000 });
        
        // Atualiza a tela limpando caches
        demandasCache = null; dashPessoas = null; $('grid-demandas').dataset.carregado = '';
        carregarDashboard();
        if (ultimaBuscaFeita) executarBusca();
      } catch (e) {
        console.error(e);
        $('aloc-erro-geral').innerHTML = `${icon('alert')}<span>Erro na alocação: ${esc(msgErro(e))}</span>`;
        toast("Falha ao registrar alocação no banco.", { tipo: 'error' });
      } finally {
        setLoading(btn, false);
      }
    }


    // ==========================================
    // 2. DASHBOARD COM DADOS REAIS DO POSTGRESQL
    // ==========================================
    let dashSort = 'disp-desc';

    function skeletonLinhasDash() {
      $('dash-tabela-bench').innerHTML = [1, 2, 3, 4, 5].map(() => `<tr><td colspan="4" class="td-full"><div class="sk" style="height:38px"></div></td></tr>`).join('');
    }

    async function carregarDashboard() {
      const tabela = $('dash-tabela-bench');
      const primeira = dashPessoas === null;
      const btn = $('btn-refresh-dash');
      if (primeira) {
        skeletonLinhasDash();
        ['dash-bench', 'dash-parcial', 'dash-demandas', 'dash-skill'].forEach(id => { $(id).innerText = '0'; $(id).classList.add('is-loading-val'); });
      }
      setLoading(btn, true, 'Atualizando…');
      try {
        const [pessoasRes, demandasRes] = await Promise.all([fetch(ENDPOINTS.DASHBOARD), fetch(ENDPOINTS.DEMANDAS)]);
        if (!pessoasRes.ok || !demandasRes.ok) throw new Error('Falha ao consultar os endpoints do PostgreSQL');
        const [pt, dt] = await Promise.all([pessoasRes.text(), demandasRes.text()]);
        const pessoas = lista(pt ? JSON.parse(pt) : []);
        const demandas = lista(dt ? JSON.parse(dt) : []);
        demandasCache = demandas;
        const livres = pessoas.filter(p => Number(p.disponibilidade) > 0);
        dashPessoas = livres;
        const contagem = new Map();
        livres.forEach(p => listaTexto(p.skills).forEach(s => contagem.set(s, (contagem.get(s) || 0) + 1)));
        const top = [...contagem.entries()].sort((a, b) => b[1] - a[1])[0];
        const bench = livres.filter(p => Number(p.disponibilidade) === 100).length;
        ['dash-bench', 'dash-parcial', 'dash-demandas', 'dash-skill'].forEach(id => $(id).classList.remove('is-loading-val'));
        $('dash-bench').innerText = bench;
        $('dash-parcial').innerText = livres.length - bench;
        $('dash-demandas').innerText = demandas.length;
        $('dash-skill').innerText = top ? top[0] : '-';
        $('dash-skill-desc').innerText = top ? `Presente em ${top[1]} ${top[1] === 1 ? 'profissional livre' : 'profissionais livres'}.` : 'Sem skills registradas entre os livres.';
        renderTabelaBench();
      } catch (error) {
        console.error(error);
        ['dash-bench', 'dash-parcial', 'dash-demandas', 'dash-skill'].forEach(id => { $(id).classList.remove('is-loading-val'); if (primeira) $(id).innerText = '-'; });
        if (primeira) {
          tabela.innerHTML = `<tr><td colspan="4" class="td-full">${estado({
            icone: 'alert', erro: true, compacto: true, titulo: 'Não foi possível carregar o PostgreSQL',
            texto: msgErro(error),
            extra: `<button type="button" class="btn btn-ghost btn-sm" data-action="recarregar-dashboard">${icon('refresh')}<span>Tentar novamente</span></button>`
          })}</td></tr>`;
        } else {
          toast(msgErro(error), { tipo: 'error', titulo: 'Falha ao atualizar o dashboard' });
        }
      } finally {
        setLoading(btn, false);
      }
    }

    function renderTabelaBench() {
      if (dashPessoas === null) return;
      const termo = $('dash-busca').value.trim().toLowerCase();
      const filtro = $('dash-filtro').value;
      dashSort = $('dash-ordem').value;
      let itens = dashPessoas.filter(p => {
        const d = Number(p.disponibilidade);
        if (filtro === 'bench' && d !== 100) return false;
        if (filtro === 'parcial' && d === 100) return false;
        if (!termo) return true;
        return [p.nome, p.cargo, p.senioridade, ...listaTexto(p.skills)].some(v => String(v ?? '').toLowerCase().includes(termo));
      });
      const [campo, dir] = dashSort.split('-');
      const f = dir === 'asc' ? 1 : -1;
      itens.sort((a, b) => campo === 'nome'
        ? f * String(a.nome ?? '').localeCompare(String(b.nome ?? ''), 'pt-BR')
        : f * (Number(a.disponibilidade) - Number(b.disponibilidade)) || String(a.nome ?? '').localeCompare(String(b.nome ?? ''), 'pt-BR'));
      $('th-nome').setAttribute('aria-sort', campo === 'nome' ? (dir === 'asc' ? 'ascending' : 'descending') : 'none');
      $('th-disp').setAttribute('aria-sort', campo === 'disp' ? (dir === 'asc' ? 'ascending' : 'descending') : 'none');

      dashVisiveis = itens; // Snapshot para clique do modal

      const media = dashPessoas.length ? Math.round(dashPessoas.reduce((s, p) => s + Number(p.disponibilidade), 0) / dashPessoas.length) : 0;
      $('dash-contagem').textContent = `Exibindo ${itens.length} de ${dashPessoas.length} • Disponibilidade média: ${media}%`;

      const tabela = $('dash-tabela-bench');
      if (!dashPessoas.length) {
        tabela.innerHTML = `<tr><td colspan="4" class="td-full">${estado({ icone: 'users', compacto: true, titulo: 'Nenhum talento disponível', texto: 'Todos os profissionais estão totalmente alocados no momento.' })}</td></tr>`;
        return;
      }
      if (!itens.length) {
        tabela.innerHTML = `<tr><td colspan="4" class="td-full">${estado({ icone: 'search', compacto: true, titulo: 'Nada encontrado com estes filtros', extra: `<button type="button" class="btn btn-ghost btn-sm" data-action="dash-limpar-filtros">Limpar filtros</button>` })}</td></tr>`;
        return;
      }
      tabela.innerHTML = itens.map((p, idx) => {
        const d = Number(p.disponibilidade);
        const livre = d === 100;
        const skills = listaTexto(p.skills);
        // Cada linha clicável com sua ação global do modal
        return `<tr data-action="ver-perfil" data-ctx="dash" data-i="${idx}">
          <td data-label="Profissional"><div class="person">${avatar(p.nome)}<span class="p-name">${esc(p.nome)}</span></div></td>
          <td data-label="Cargo / Senioridade"><div>${esc(p.cargo) || '-'}</div>${p.senioridade ? `<div class="p-sub">${esc(p.senioridade)}</div>` : ''}</td>
          <td data-label="Principais skills"><div class="tags" title="${esc(skills.join(', '))}">${skills.length
            ? skills.slice(0, 4).map(s => `<span class="tag">${esc(s)}</span>`).join('') + (skills.length > 4 ? `<span class="tag more">+${skills.length - 4}</span>` : '')
            : '<span class="p-sub">-</span>'}</div></td>
          <td data-label="Disponibilidade"><div class="disp">
            <div class="disp-h"><b style="color:${livre ? '#6ee7b7' : '#fcd34d'}">${esc(p.disponibilidade)}% livre</b><span class="badge ${livre ? 'ok' : 'warn'}">${livre ? 'Bench' : 'Parcial'}</span></div>
            ${bar(d, livre ? 'ok' : 'warn')}</div></td>
        </tr>`;
      }).join('');
    }

    // ==========================================
    // 3. DEMANDAS E PROJETOS REAIS
    // ==========================================
    function skeletonDemandas() {
      $('grid-demandas').innerHTML = [1, 2, 3, 4].map(() => `<div class="card dem"><div class="sk" style="height:22px;width:65%"></div><div class="sk" style="height:14px;width:45%"></div><div class="sk" style="height:60px"></div></div>`).join('');
    }

    async function carregarDemandas() {
      const grid = $('grid-demandas');
      const primeira = !grid.dataset.carregado;
      const btn = $('btn-refresh-dem');
      if (primeira) skeletonDemandas();
      setLoading(btn, true, 'Atualizando…');
      try {
        const res = await fetch(ENDPOINTS.DEMANDAS);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const t = await res.text();
        demandasCache = lista(t ? JSON.parse(t) : []);
        grid.dataset.carregado = '1';
        renderDemandas();
      } catch (error) {
        console.error(error);
        if (primeira) {
          grid.innerHTML = estado({
            icone: 'alert', erro: true, titulo: 'Não foi possível carregar as demandas do PostgreSQL',
            texto: error instanceof TypeError ? msgErro(error) : String(error.message),
            extra: `<button type="button" class="btn btn-ghost btn-sm" data-action="recarregar-demandas">${icon('refresh')}<span>Tentar novamente</span></button>`
          });
          grid.style.display = 'block';
        } else toast(msgErro(error), { tipo: 'error', titulo: 'Falha ao atualizar demandas' });
      } finally { setLoading(btn, false); }
    }

    function renderDemandas() {
      const grid = $('grid-demandas');
      grid.style.display = '';
      const termo = $('dem-busca').value.trim().toLowerCase();
      const todas = demandasCache || [];
      const itens = todas.filter(d => !termo || [d.nome, d.id, ...lista(d.colaboradores).map(p => p.nome)].some(v => String(v ?? '').toLowerCase().includes(termo)));
      $('dem-contagem').textContent = `${itens.length} de ${todas.length} ${todas.length === 1 ? 'demanda' : 'demandas'}`;
      if (!todas.length) { grid.style.display = 'block'; grid.innerHTML = estado({ icone: 'folder', titulo: 'Nenhuma demanda ativa', texto: 'Quando houver projetos em andamento, eles aparecerão aqui com os profissionais alocados.' }); return; }
      if (!itens.length) { grid.style.display = 'block'; grid.innerHTML = estado({ icone: 'search', titulo: 'Nenhuma demanda encontrada', texto: 'Ajuste o termo de busca.' }); return; }
      
      grid.innerHTML = itens.map((d) => {
        const dIndex = demandasCache.indexOf(d); // resgata o ID original no cache global p/ modal
        const colabs = lista(d.colaboradores);
        const total = d.pessoas ?? colabs.length;
        const LIM = 6;
        return `<article class="card dem">
          <div class="dem-top">
            <div><h3>${esc(d.nome)}</h3><span class="idpill">ID ${esc(d.id)}</span>${d.andamento ? `<span class="statuspill">${esc(d.andamento)}</span>` : ''}</div>
            <span class="count-pill" title="Profissionais alocados">${icon('users')}${esc(total)}</span>
          </div>
          <p class="period">${icon('clock')}<span><b>${esc(fmtData(d.inicio))}</b> até <b>${esc(fmtData(d.termino))}</b></span></p>
          <div>
            <p class="eyebrow" style="margin-bottom:8px">Profissionais (${esc(total)})</p>
            ${colabs.length ? `<ul class="people">${colabs.map((p, k) => `<li class="${k >= LIM ? 'more-hidden' : ''}" data-action="ver-perfil" data-ctx="demanda" data-di="${dIndex}" data-ci="${k}">${avatar(p.nome, true)}<span>${esc(p.nome)}</span></li>`).join('')}</ul>
              ${colabs.length > LIM ? `<button type="button" class="link-btn" data-action="dem-mais" aria-expanded="false" data-total="${colabs.length - LIM}">Ver mais ${colabs.length - LIM}</button>` : ''}`
              : '<p class="empty-line">Ninguém alocado.</p>'}
          </div>
        </article>`;
      }).join('');
    }

    // ==========================================
    // 4. FAVORITOS
    // ==========================================
    let ocultos = new Set();
    try { ocultos = new Set(JSON.parse(localStorage.getItem('inhire_fav_ocultos') || '[]')); } catch (e) {}
    const salvarOcultos = () => { try { localStorage.setItem('inhire_fav_ocultos', JSON.stringify([...ocultos])); } catch (e) {} };
    const favKey = x => [x.id ?? x.id_favorito ?? '', x.id_profissional ?? '', x.nome_profissional ?? ''].join('|');

   async function salvarFavoritoCand(cand, btn) {
      setLoading(btn, true, 'Salvando…');
      try {
        // Recolhe as skills do candidato considerando as diferentes propriedades possíveis
        const skillsDoCand = cand.skills || cand.skills_atendidas || cand.todas_skills_do_colaborador || [];

        const dados = await requisitar(ENDPOINTS.SALVAR_FAV, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            id_gerente: 1, 
            id_profissional: cand.id, 
            nome_profissional: cand.nome,
            origem: cand.tipo_base === 'interno' ? 'SGD (Interno)' : 'Externo',
            cargo: cand.cargo, 
            senioridade: cand.senioridade,
            score_ranking: num(cand.aderencia_skills, 100), 
            disponibilidade_media: num(cand.tempo_livre, 100),
            skills: Array.isArray(skillsDoCand) ? skillsDoCand : []
          })
        });
        favoritosCache = null;
        toast((dados && dados.mensagem) || `${cand.nome} foi adicionado aos favoritos.`, { tipo: 'success', titulo: 'Favorito salvo' });
      } catch (e) {
        console.error(e);
        toast(msgErro(e), { tipo: 'error', titulo: 'Não foi possível favoritar' });
      } finally { setLoading(btn, false); }
    }
    function salvarFavorito(index, btn) { return salvarFavoritoCand(ultimoRanking[index], btn); }

    async function carregarFavoritos() {
      const div = $('lista-favoritos');
      const primeira = favoritosCache === null;
      const btn = $('btn-refresh-fav');
      if (primeira) div.innerHTML = [1, 2, 3].map(() => `<div class="card fav"><div class="sk" style="height:20px;width:60%"></div><div class="sk" style="height:14px;width:40%"></div><div class="sk" style="height:34px"></div></div>`).join('');
      setLoading(btn, true, 'Atualizando…');
      try {
        const res = await fetch(ENDPOINTS.LISTAR_FAV);
        if (!res.ok) throw new Error(`HTTP ${res.status}`);
        const text = await res.text();
        favoritosCache = lista(text ? JSON.parse(text) : []);
        renderFavoritos();
      } catch (e) {
        console.error(e);
        if (primeira) {
          div.style.display = 'block';
          div.innerHTML = estado({
            icone: 'alert', erro: true, titulo: 'Erro ao carregar favoritos', texto: e instanceof TypeError ? msgErro(e) : String(e.message),
            extra: `<button type="button" class="btn btn-ghost btn-sm" data-action="recarregar-favoritos">${icon('refresh')}<span>Tentar novamente</span></button>`
          });
        } else toast(msgErro(e), { tipo: 'error', titulo: 'Falha ao atualizar favoritos' });
      } finally { setLoading(btn, false); }
    }

    function renderFavoritos() {
      const div = $('lista-favoritos');
      div.style.display = '';
      const todos = favoritosCache || [];
      favoritosVisiveis = todos.filter(x => !ocultos.has(favKey(x)));
      const nOcultos = todos.length - favoritosVisiveis.length;
      $('fav-aviso').innerHTML = nOcultos
        ? `${icon('info')}<span>${nOcultos} ${nOcultos === 1 ? 'favorito removido da lista' : 'favoritos removidos da lista'} neste navegador. <button type="button" class="link-btn" style="display:inline" data-action="fav-restaurar">Restaurar</button></span>` : '';
      if (!favoritosVisiveis.length) {
        div.style.display = 'block';
        div.innerHTML = estado({
          icone: 'star', titulo: 'Nenhum favorito ainda',
          texto: 'Faça uma busca no painel InHire Copilot e toque em “Favoritar” nos candidatos que quiser acompanhar. Eles aparecerão aqui.',
          extra: `<button type="button" class="btn btn-primary btn-sm" data-action="focar-busca">${icon('search')}<span>Ir para a busca</span></button>`
        });
        return;
      }
      div.innerHTML = favoritosVisiveis.map((x, i) => {
        const interno = /interno|sgd/i.test(String(x.origem || ''));
        const score = x.score_ranking, disp = x.disponibilidade_media;
        
        // Garante que pegamos num array válido de skills do favorito
        const skillsArray = Array.isArray(x.skills) ? x.skills : [];

        return `<article class="card fav" data-action="ver-perfil" data-ctx="fav" data-i="${i}">
          <div class="fav-top">${avatar(x.nome_profissional)}
            <div style="min-width:0">
              <h3>${esc(x.nome_profissional)}</h3>
              <p class="p-sub">${esc(x.cargo ?? '—')}${x.senioridade ? ` • ${esc(x.senioridade)}` : ''}</p>
            </div>
          </div>
          <div class="badges" style="margin:0">
            ${x.origem ? `<span class="badge ${interno ? 'int' : 'ext'}">${esc(x.origem)}</span>` : ''}
            ${score !== undefined && score !== null ? `<span class="badge ok">Aderência ${esc(score)}%</span>` : ''}
            ${disp !== undefined && disp !== null ? `<span class="badge warn">Disp. ${esc(disp)}%</span>` : ''}
          </div>
          
          <!-- Renderiza as etiquetas de skills se existirem -->
          ${skillsArray.length > 0 ? `
            <div class="skills-list" style="display:flex; flex-wrap:wrap; gap:4px; margin-top:8px;">
              ${skillsArray.map(s => `<span class="badge" style="background:rgba(255,255,255,0.08); color:#fff; font-size:11px;">${esc(s)}</span>`).join('')}
            </div>
          ` : ''}

          <div class="fav-actions">
            <!-- Os botões internos não disparam o evento da Article Card por conta do prevent padrão/delegação -->
            <button type="button" class="btn btn-ghost btn-sm" data-action="ver-perfil" data-ctx="fav" data-i="${i}">${icon('eye')}<span>Ver informações</span></button>
            <button type="button" class="btn btn-danger btn-sm" data-action="fav-remover" data-i="${i}">${icon('trash')}<span>Remover</span></button>
          </div>
        </article>`;
      }).join('');
    }

    async function removerFavorito(x) {
      const ok = await confirmar({
        titulo: 'Remover dos favoritos?',
        mensagem: `${x.nome_profissional || 'O profissional'} deixará de aparecer nesta lista, neste navegador. O registro no banco não é apagado, pois não há endpoint de exclusão no n8n.`,
        ok: 'Remover da lista'
      });
      if (!ok) return;
      ocultos.add(favKey(x)); salvarOcultos(); renderFavoritos();
      toast(`${x.nome_profissional || 'Profissional'} removido da lista de favoritos.`, { tipo: 'info' });
    }

    // ==========================================
    // 5. REMANEJAMENTO
    // ==========================================
    const CAMPOS_REM = ['rem-demanda-antiga', 'rem-pct-antiga', 'rem-demanda-nova', 'rem-pct-nova', 'rem-mes', 'rem-ano'];

    function abrirModalRemanejar(index) { abrirModalRemanejarCand(ultimoRanking[index]); }

    function abrirModalRemanejarCand(cand) {
      candidatoRem = cand;
      remTentou = false; remToques.clear();
      $('rem-id-colab').value = cand.id ?? cand.id_colaborador ?? cand.id_talento;
      $('rem-nome').textContent = cand.nome;
      $('rem-avatar').textContent = iniciais(cand.nome);
      $('rem-avatar').style.setProperty('--h', hue(cand.nome));
      $('rem-info').textContent = [cand.cargo, cand.senioridade, `Alocação atual: ${cand.alocacao_atual ?? '—'}`, `Livre: ${cand.tempo_livre ?? '—'}`].filter(Boolean).join(' • ');
      const projs = lista(cand.projetos_atuais);
      $('rem-demanda-antiga').innerHTML = projs.length
        ? projs.map(p => `<option value="${esc(p.id_demanda)}">${esc(p.nome_demanda)} (ID ${esc(p.id_demanda)})</option>`).join('')
        : '<option value="">Nenhum projeto atual encontrado</option>';
      $('rem-pct-antiga').value = 50;
      $('rem-pct-nova').value = 50;
      $('rem-demanda-nova').value = '';
      const hoje = new Date();
      $('rem-mes').innerHTML = MESES.map(m => `<option value="${m}">${m}</option>`).join('');
      $('rem-mes').value = MESES[hoje.getMonth()];
      $('rem-ano').value = hoje.getFullYear();
      $('rem-erro-geral').innerHTML = '';
      popularListaDemandas('rem-demanda-lista', 'rem-lista-wrap');
      renderRemValidacao();
      abrirModal('modal-remanejar', 'rem-demanda-antiga');
    }

    async function popularListaDemandas(selId, wrapId) {
      const sel = $(selId);
      const montar = () => {
        sel.innerHTML = '<option value="">Selecione para preencher o ID…</option>' + (demandasCache || []).map(d => `<option value="${esc(d.id)}">${esc(d.nome)} (ID ${esc(d.id)})</option>`).join('');
        $(wrapId).classList.toggle('hidden', !(demandasCache && demandasCache.length));
      };
      if (demandasCache) return montar();
      $(wrapId).classList.add('hidden');
      try {
        const t = await (await fetch(ENDPOINTS.DEMANDAS)).text();
        demandasCache = lista(t ? JSON.parse(t) : []);
        montar();
      } catch (e) { /* opcional */ }
    }

    function validarRemanejamento() {
      const e = {};
      const isInt = s => /^\d+$/.test(s);
      const dAnt = $('rem-demanda-antiga').value;
      const pA = $('rem-pct-antiga').value.trim();
      const dN = $('rem-demanda-nova').value.trim();
      const pN = $('rem-pct-nova').value.trim();
      const mes = $('rem-mes').value;
      const ano = $('rem-ano').value.trim();
      if (!dAnt) e['rem-demanda-antiga'] = 'Selecione a demanda atual do profissional.';
      if (pA === '') e['rem-pct-antiga'] = 'Informe o novo percentual da demanda atual.';
      else if (!isInt(pA) || +pA > 100) e['rem-pct-antiga'] = 'Use um número inteiro entre 0 e 100.';
      if (dN === '') e['rem-demanda-nova'] = 'Informe o ID da nova demanda.';
      else if (!isInt(dN) || +dN < 1) e['rem-demanda-nova'] = 'Use um ID numérico válido.';
      else if (dAnt && String(+dN) === String(+dAnt)) e['rem-demanda-nova'] = 'A nova demanda deve ser diferente da demanda atual.';
      if (pN === '') e['rem-pct-nova'] = 'Informe o percentual da nova demanda.';
      else if (!isInt(pN) || +pN < 1 || +pN > 100) e['rem-pct-nova'] = 'Use um número inteiro entre 1 e 100.';
      if (!e['rem-pct-antiga'] && !e['rem-pct-nova'] && +pA + +pN > 100) e['rem-pct-nova'] = `A soma dos percentuais (${+pA + +pN}%) não pode passar de 100%.`;
      if (!MESES.includes(mes)) e['rem-mes'] = 'Selecione o mês.';
      if (ano === '') e['rem-ano'] = 'Informe o ano.';
      else if (!isInt(ano) || +ano < 2000 || +ano > 2100) e['rem-ano'] = 'Informe um ano entre 2000 e 2100.';
      return e;
    }

    function renderRemValidacao() {
      const erros = validarRemanejamento();
      CAMPOS_REM.forEach(id => {
        const msg = (remTentou || remToques.has(id)) ? erros[id] : '';
        const el = $(id), out = $(`err-${id}`);
        out.innerHTML = msg ? `${icon('alert', '" style="width:14px;height:14px;margin-top:2px')}<span>${esc(msg)}</span>` : '';
        if (msg) el.setAttribute('aria-invalid', 'true'); else el.removeAttribute('aria-invalid');
      });
      const c = candidatoRem || {};
      const nome = esc(c.nome ?? '');
      const sel = $('rem-demanda-antiga');
      const nomeAnt = sel.selectedOptions[0] ? esc(sel.selectedOptions[0].textContent) : '—';
      const dN = $('rem-demanda-nova').value.trim();
      const dNova = (demandasCache || []).find(d => String(d.id) === dN);
      const pA = $('rem-pct-antiga').value || '—', pN = $('rem-pct-nova').value || '—';
      $('rem-resumo').innerHTML = `
        <li>${icon('swap')}<span><b>${nome}</b> passa a ter <b>${esc(pA)}%</b> em <b>${nomeAnt}</b>.</span></li>
        <li>${icon('plus')}<span>Será alocado(a) na demanda <b>${dN ? `ID ${esc(dN)}${dNova ? ` — ${esc(dNova.nome)}` : ''}` : 'a definir'}</b> com <b>${esc(pN)}%</b>.</span></li>
        <li>${icon('clock')}<span>Período: <b>${esc($('rem-mes').value)}/${esc($('rem-ano').value || '—')}</b>.</span></li>`;
      return erros;
    }

    async function confirmarRemanejamento() {
      if (remEnviando) return;
      remTentou = true;
      const erros = renderRemValidacao();
      const primeiro = CAMPOS_REM.find(id => erros[id]);
      if (primeiro) { $(primeiro).focus(); toast('Corrija os campos destacados antes de confirmar.', { tipo: 'warn' }); return; }
      const btn = $('btn-confirmar-rem');
      remEnviando = true; setLoading(btn, true, 'Remanejando…');
      $('btn-cancelar-rem').disabled = true;
      $('rem-erro-geral').innerHTML = '';
      try {
        await requisitar(ENDPOINTS.REMANEJAR, {
          method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            id_colaborador: $('rem-id-colab').value,
            id_demanda_antiga: $('rem-demanda-antiga').value,
            nova_porcentagem_demanda_antiga: $('rem-pct-antiga').value,
            id_demanda_nova: $('rem-demanda-nova').value,
            porcentagem_nova_demanda: $('rem-pct-nova').value,
            mes: $('rem-mes').value, ano: $('rem-ano').value
          })
        });
        remEnviando = false;
        const nome = candidatoRem ? candidatoRem.nome : 'Profissional';
        fecharModal('modal-remanejar');
        toast(`Alocação de ${nome} atualizada no banco.`, { tipo: 'success', titulo: 'Remanejamento concluído' });
        if (ultimaBuscaFeita) executarBusca();
        if (dashPessoas !== null || demandasCache) { demandasCache = null; dashPessoas = null; $('grid-demandas').dataset.carregado = ''; }
      } catch (e) {
        console.error(e);
        $('rem-erro-geral').innerHTML = `${icon('alert')}<span>Não foi possível remanejar: ${esc(msgErro(e))} Nenhuma alteração foi confirmada; tente novamente.</span>`;
        toast(msgErro(e), { tipo: 'error', titulo: 'Falha no remanejamento' });
      } finally {
        remEnviando = false; setLoading(btn, false); $('btn-cancelar-rem').disabled = false;
      }
    }

    // ==========================================
    // 6. COMPARAÇÃO
    // ==========================================
    function toggleComparar(index) {
      const cand = ultimoRanking[index];
      if (!cand) return;
      const k = candKey(cand);
      const existe = selecionadosComparacao.some(s => candKey(s) === k);
      if (existe) selecionadosComparacao = selecionadosComparacao.filter(s => candKey(s) !== k);
      else {
        if (selecionadosComparacao.length >= MAX_COMPARACAO) {
          toast(`Limite de ${MAX_COMPARACAO} profissionais na comparação. Remova um para adicionar outro.`, { tipo: 'warn', titulo: 'Limite atingido' });
          return;
        }
        selecionadosComparacao.push(cand);
      }
      sincronizarBotoesComparar();
      renderizarComparacao();
    }
    function sincronizarBotoesComparar() {
      document.querySelectorAll('[data-action="comparar"]').forEach(b => {
        b.setAttribute('aria-pressed', String(selecionadosComparacao.some(s => candKey(s) === b.dataset.key)));
      });
    }

    function renderizarComparacao() {
      const sel = selecionadosComparacao;
      const n = sel.length;
      $('count-comp').innerText = n;
      $('comp-contador').textContent = `${n} de ${MAX_COMPARACAO} selecionados`;
      $('btn-comp-limpar').disabled = n === 0;
      const aviso = $('comp-aviso');
      const grid = $('grid-comparacao');
      const ins = $('comp-insights');

      if (n === 0) {
        aviso.className = 'notice'; aviso.innerHTML = ''; ins.innerHTML = ''; grid.style.display = 'block';
        grid.innerHTML = estado({
          icone: 'columns', titulo: 'Nenhum profissional na comparação',
          texto: `Faça uma busca no painel InHire Copilot e use o botão “Comparar” nos cards dos resultados. Você pode comparar até ${MAX_COMPARACAO} profissionais.`,
          extra: `<button type="button" class="btn btn-primary btn-sm" data-action="focar-busca">${icon('search')}<span>Ir para a busca</span></button>`
        });
        return;
      }
      if (n >= MAX_COMPARACAO) { aviso.className = 'notice warn'; aviso.innerHTML = `${icon('alert')}<span>Limite de ${MAX_COMPARACAO} profissionais atingido. Remova alguém para adicionar outro candidato.</span>`; }
      else if (n === 1) { aviso.className = 'notice info'; aviso.innerHTML = `${icon('info')}<span>Adicione ao menos mais um profissional para ver as diferenças entre os candidatos.</span>`; }
      else { aviso.className = 'notice'; aviso.innerHTML = ''; }

      const aders = sel.map(c => num(c.aderencia_skills));
      const livres = sel.map(c => num(c.tempo_livre));
      const maxA = n > 1 ? Math.max(...aders.map(v => v ?? -1)) : null;
      const maxL = n > 1 ? Math.max(...livres.map(v => v ?? -1)) : null;
      const sets = sel.map(c => new Set(listaTexto(c.skills_atendidas)));
      const comuns = n > 1 ? [...sets[0]].filter(s => sets.every(st => st.has(s))) : [];

      if (n > 1) {
        const nomes = (arr, max) => sel.filter((c, i) => arr[i] === max && max >= 0).map(c => c.nome);
        const nA = nomes(aders, maxA), nL = nomes(livres, maxL);
        const diretos = sel.filter(c => !precisaRemanejar(c)).length;
        ins.innerHTML = `
          <div class="insight"><small>Maior aderência</small><b>${esc(nA.join(' e ') || '—')}</b> <span>${maxA >= 0 ? `(${maxA}%)` : ''}</span></div>
          <div class="insight"><small>Mais disponível</small><b>${esc(nL.join(' e ') || '—')}</b> <span>${maxL >= 0 ? `(${maxL}% livre)` : ''}</span></div>
          <div class="insight" style="background:rgba(79,140,255,.07);border-color:rgba(79,140,255,.25)"><small style="color:#93bbff">Prontos para alocação direta</small><b>${diretos} de ${n}</b> <span>${n - diretos ? `${n - diretos} exige(m) remanejamento` : 'nenhum exige remanejamento'}</span></div>`;
      } else ins.innerHTML = '';

      grid.style.display = 'grid';
      grid.style.gridTemplateColumns = `repeat(${Math.min(n, 4)}, minmax(240px, 1fr))`;
      grid.innerHTML = (n > 1 ? `<div class="legend" style="grid-column:1/-1"><span class="tag diff">Skill diferencial</span><span>aparece só em parte dos selecionados</span><span class="tag common">Skill comum</span><span>presente em todos</span></div>` : '') +
        sel.map((c, i) => {
          const rem = precisaRemanejar(c);
          const melhorA = n > 1 && aders[i] !== null && aders[i] === maxA;
          const melhorL = n > 1 && livres[i] !== null && livres[i] === maxL;
          const skills = listaTexto(c.skills_atendidas);
          return `<article class="card cmp-card ${melhorA && melhorL ? 'best-any' : ''}" data-action="ver-perfil" data-ctx="comp" data-i="${i}">
            <div class="cmp-head">
              <div style="display:flex;gap:12px;align-items:flex-start;min-width:0">${avatar(c.nome)}<div style="min-width:0"><h3>${esc(c.nome)}</h3>
                <div class="badges"><span class="badge ${tipoInterno(c) ? 'int' : 'ext'}">${tipoInterno(c) ? 'Interno (SGD)' : 'Externo'}</span></div></div></div>
              <button type="button" class="btn btn-ghost btn-sm" data-action="cmp-remover" data-key="${esc(candKey(c))}" aria-label="Remover ${esc(c.nome)} da comparação">${icon('x')}<span>Remover</span></button>
            </div>
            <dl class="dl">
              <div><dt>Cargo</dt><dd>${esc(c.cargo ?? '—')}</dd></div>
              <div><dt>Senioridade</dt><dd>${esc(c.senioridade ?? '—')}</dd></div>
              <div><dt>Aderência às skills ${melhorA ? '<span class="badge best">Maior</span>' : ''}</dt><dd class="strong">${esc(c.aderencia_skills ?? '—')}</dd>${bar(aders[i], 'brand')}</div>
              <div><dt>Competências atendidas</dt><dd>${skills.length ? `<div class="tags">${skills.map(s => `<span class="tag ${n > 1 ? (comuns.includes(s) ? 'common' : 'diff') : 'brand'}">${esc(s)}</span>`).join('')}</div>` : '—'}</dd></div>
              <div><dt>Disponibilidade ${melhorL ? '<span class="badge best">Maior</span>' : ''}</dt><dd class="strong">${esc(c.tempo_livre ?? '—')}</dd>${bar(livres[i], clsDisp(livres[i]))}</div>
              <div><dt>Alocação atual</dt><dd>${esc(c.alocacao_atual ?? '—')}</dd></div>
              <div><dt>Situação</dt><dd><span class="badge ${rem ? 'warn' : 'ok'}">${rem ? 'Requer remanejamento' : 'Alocação direta'}</span></dd></div>
            </dl>
            <div class="actions" style="padding-top:12px">
              ${rem
                ? `<button type="button" class="btn btn-warn btn-sm btn-main" data-action="cmp-acao" data-key="${esc(candKey(c))}">${icon('swap')}<span>Remanejar alocação</span></button>`
                : `<button type="button" class="btn btn-ok btn-sm btn-main" data-action="cmp-acao" data-key="${esc(candKey(c))}">${icon('plus')}<span>Adicionar ao projeto</span></button>`}
              <button type="button" class="btn btn-ghost btn-sm" data-action="cmp-fav" data-key="${esc(candKey(c))}">${icon('star')}<span>Favoritar</span></button>
            </div>
          </article>`;
        }).join('');
    }

    // ==========================================
    // NAVEGAÇÃO DE ABAS
    // ==========================================
    function mudarAba(abaId) {
      const chatAtivo = abaId === 'chat';
      $('app').classList.toggle('chat-primary', chatAtivo);
      ABAS.forEach(a => {
        const sec = $(`sec-${a}`), tab = $(`tab-${a}`), on = a === abaId;
        if (sec) sec.classList.toggle('hidden', !on);
        if (tab) {
          tab.classList.toggle('active', on);
          tab.setAttribute('aria-selected', String(on));
          tab.tabIndex = on ? 0 : -1;
        }
      });
      $('content').scrollTop = 0;
      if (abaId === 'dashboard') carregarDashboard();
      if (abaId === 'demandas') carregarDemandas();
      if (abaId === 'comparar') renderizarComparacao();
      if (abaId === 'favoritos') carregarFavoritos();
    }

    // ==========================================
    // EVENTOS (delegação central)
    // ==========================================
    document.addEventListener('click', async e => {
      const el = e.target.closest('[data-action]');
      if (!el || el.disabled) return;
      const a = el.dataset.action;
      const i = el.dataset.i !== undefined ? Number(el.dataset.i) : null;
      
      switch (a) {
        case 'toggle-sidebar': definirSidebar(!sidebarAberta()); break;
        case 'toggle-full': definirTelaCheia(!app.classList.contains('sb-full')); break;
        case 'abrir-sidebar': definirSidebar(true); setTimeout(() => $('input-ia').focus(), 260); break;
        case 'fechar-sidebar': definirSidebar(false); break;
        case 'focar-busca': focarBusca(); break;
        case 'exemplo': $('input-ia').value = el.dataset.texto; $('input-ia').focus(); break;
        case 'buscar': executarBusca(); break;
        case 'aba': mudarAba(el.dataset.aba); break;
        
        case 'acao-principal': {
          const c = ultimoRanking[i]; if (!c) break;
          precisaRemanejar(c) ? abrirModalRemanejar(i) : alocarDireto(i); break;
        }
        case 'favoritar': salvarFavorito(i, el); break;
        case 'comparar': toggleComparar(i); break;
        
        case 'cmp-remover':
          selecionadosComparacao = selecionadosComparacao.filter(s => candKey(s) !== el.dataset.key);
          sincronizarBotoesComparar(); renderizarComparacao(); break;
        case 'cmp-limpar':
          selecionadosComparacao = []; sincronizarBotoesComparar(); renderizarComparacao();
          toast('Comparação limpa.', { tipo: 'info', duracao: 2500 }); break;
        case 'cmp-acao': {
          const c = selecionadosComparacao.find(s => candKey(s) === el.dataset.key); if (!c) break;
          precisaRemanejar(c) ? abrirModalRemanejarCand(c) : alocarDiretoCand(c); break;
        }
        case 'cmp-fav': {
          const c = selecionadosComparacao.find(s => candKey(s) === el.dataset.key); if (c) salvarFavoritoCand(c, el); break;
        }
        
        case 'recarregar-dashboard': carregarDashboard(); break;
        case 'recarregar-demandas': carregarDemandas(); break;
        case 'recarregar-favoritos': carregarFavoritos(); break;
        
        case 'dash-limpar-filtros':
          $('dash-busca').value = ''; $('dash-filtro').value = 'todos'; renderTabelaBench(); break;
        case 'dash-sort': {
          const campo = el.dataset.campo, [c, d] = $('dash-ordem').value.split('-');
          $('dash-ordem').value = campo === 'nome' ? (c === 'nome' && d === 'asc' ? 'nome-desc' : 'nome-asc') : (c === 'disp' && d === 'desc' ? 'disp-asc' : 'disp-desc');
          renderTabelaBench(); break;
        }
        
        case 'dem-mais': {
          const ul = el.previousElementSibling; const ex = ul.classList.toggle('expanded');
          el.setAttribute('aria-expanded', String(ex));
          el.textContent = ex ? 'Ver menos' : `Ver mais ${el.dataset.total}`; break;
        }
        
        case 'fav-remover': favoritosVisiveis[i] && removerFavorito(favoritosVisiveis[i]); break;
        case 'fav-restaurar': ocultos.clear(); salvarOcultos(); renderFavoritos(); break;
        
        case 'ver-perfil': {
          const ctx = el.dataset.ctx;
          let prof = null;
          
          if (ctx === 'busca') prof = ultimoRanking[i];
          else if (ctx === 'dash') prof = dashVisiveis[i];
          else if (ctx === 'comp') prof = selecionadosComparacao[i];
          else if (ctx === 'fav') prof = favoritosVisiveis[i];
          else if (ctx === 'demanda') {
            const di = num(el.dataset.di);
            const ci = num(el.dataset.ci);
            if (demandasCache && demandasCache[di] && demandasCache[di].colaboradores) {
              prof = demandasCache[di].colaboradores[ci];
            }
          }
          if (prof) abrirDetalhesProfissional(prof);
          break;
        }

        case 'confirmar-alocacao': efetivarAlocacao(); break;

        case 'fechar-modal': fecharModal(el.dataset.modalId); break;
        case 'confirmar-remanejar': confirmarRemanejamento(); break;
        case 'confirm-ok': resolverConfirm(true); break;
        case 'confirm-cancel': resolverConfirm(false); break;
      }
    });

    // Busca por formulário
    $('form-busca').addEventListener('submit', e => { e.preventDefault(); executarBusca(); });
    $('input-ia').addEventListener('keydown', e => { if (e.key === 'Enter' && (e.ctrlKey || e.metaKey)) { e.preventDefault(); $('form-busca').requestSubmit(); } });
    $('modo-disp').addEventListener('change', atualizarDicaModo);

    // Filtros
    ['dash-busca', 'dash-filtro', 'dash-ordem'].forEach(id => $(id).addEventListener(id === 'dash-busca' ? 'input' : 'change', renderTabelaBench));
    $('dem-busca').addEventListener('input', () => demandasCache && renderDemandas());

    // Modais Live Validation (Remanejar)
    const formRem = $('form-remanejar');
    formRem.addEventListener('submit', e => { e.preventDefault(); confirmarRemanejamento(); });
    formRem.addEventListener('input', e => { if (e.target.id) remToques.add(e.target.id); renderRemValidacao(); });
    formRem.addEventListener('change', e => { if (e.target.id) remToques.add(e.target.id); renderRemValidacao(); });
    formRem.addEventListener('focusout', e => { if (e.target.id && CAMPOS_REM.includes(e.target.id)) { remToques.add(e.target.id); renderRemValidacao(); } });
    formRem.addEventListener('keydown', e => {
      if (e.target.type === 'number' && ['e', 'E', '+', '-', '.', ','].includes(e.key)) e.preventDefault();
    });
    $('rem-demanda-lista').addEventListener('change', e => {
      if (e.target.value) { $('rem-demanda-nova').value = e.target.value; remToques.add('rem-demanda-nova'); renderRemValidacao(); }
    });

    // Navegação (Setas Keyboard)
    $('tab-dashboard').parentElement.addEventListener('keydown', e => {
      if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(e.key)) return;
      const tabs = ABAS.map(a => $(`tab-${a}`));
      let idx = tabs.indexOf(document.activeElement); if (idx < 0) return;
      idx = e.key === 'Home' ? 0 : e.key === 'End' ? tabs.length - 1 : (idx + (e.key === 'ArrowRight' ? 1 : -1) + tabs.length) % tabs.length;
      e.preventDefault(); tabs[idx].focus(); mudarAba(ABAS[idx]);
    });

    // INIT
    window.onload = () => {
      initSidebar();
      atualizarDicaModo();
      renderizarComparacao();
      mudarAba('chat');
    };
