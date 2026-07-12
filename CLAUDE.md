# Analytics Distribuidoras — Royal FIC

## Projeto
Dashboard PWA de inteligência comercial para a Royal FIC Distribuidora de Derivados de Petróleo, usando dados públicos da ANP (Agência Nacional do Petróleo). Hospedado no GitHub Pages: `sandroregal.github.io/CLAUDE/`

## Usuário
- **Sandro Regal** — Royal FIC, Inteligência Comercial
- Idioma: Português (pt-BR)
- Acessa principalmente pelo celular (PWA instalada)

## Arquitetura
- **Single-file app**: tudo em `index.html` (HTML + CSS + JS + dados embutidos)
- **PWA**: `manifest.json`, `sw.js` (network-first caching), ícones (192, 512, maskable)
- **Sem dependências externas** — vanilla JS, Canvas API para gráficos
- **Branch de trabalho**: `claude/fuel-distributor-analytics-kxgtsh` → merge para `main`

## Estrutura de Dados
```
RAW = {
  empresas: [...],    // 185 distribuidoras
  produtos: [...],    // Diesel S10, Diesel S500, Etanol Hidratado, Gasolina C, Oleo Combustivel, Outros Diesel
  segmentos: [...],   // Consumidor Final, Posto Bandeirado, Posto Branco, TRR
  ufs: [...],         // 27 UFs do Brasil
  dados: [            // ~96k rows agregados
    [ano, mes, empresa_idx, produto_idx, segmento_idx, uf_idx, volume_mil_m3]
    // índices: 0=ano, 1=mes, 2=empresa, 3=produto, 4=segmento, 5=uf, 6=volume
  ]
}
```

## Constantes Importantes
- `ROYAL_IDX` — índice da Royal FIC no array de empresas
- `ROYAL_COLOR = '#C9952E'` (dourado)
- `ROYAL_SHORT = 'Royal FIC'`
- Volume em mil m³

## Funcionalidades
1. **Filtros multi-select**: Período, Produto, Segmento, UF, Distribuidora, Top N
2. **Comparação de períodos**: toggle para comparar dois ranges
3. **KPIs**: Volume, Market Share, Posição no ranking
4. **Highlights**: Top 5 posições da Royal FIC por produto/segmento
5. **Inteligência de Mercado** (seção análise):
   - Panorama do Setor (dinâmica de produtos/segmentos — crescimento, não shares)
   - Royal FIC vs Mercado (tabelas separadas por produto e segmento, com Dif. colorida)
   - Retrovisor Competitivo (concorrentes atrás no ranking, onde avançam)
6. **Gráficos Canvas**: Ranking, Evolução mensal, Royal vs Mercado, Mix de Produtos, Segmentos, Market Share
7. **Tooltips interativos** nos gráficos
8. **Linha tracejada** para Royal FIC nos gráficos de evolução

## Design / Cores
- Palette: azul escuro `#0E4C89`, azul médio `#1565A8`, dourado `#C9952E`
- Status: verde `#0E8A5C`, vermelho `#C25B3A`
- Dark mode completo via CSS variables
- Ícones PWA: gota laranja/âmbar `#F5A623` em círculo azul `#1A5A96` sobre fundo `#0E4C89`

## Padrões de Código
- Análise de mercado: evitar redundância com outros componentes (ranking, gráficos)
- Cores na análise: usar com moderação — `var(--muted)` para labels, cor só em dados-chave
- Divisórias sutis (`.analysis-divider`) entre seções da análise
- Tabelas comparativas (`.cmp-table`) com classes `.cmp-pos`, `.cmp-neg`, `.cmp-neutral`

## Geração de Ícones
- Via Playwright headless + Canvas API
- `executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'`
- Scripts em `/tmp/.../scratchpad/gen-icons.js` + `gen-icons3.html`

## Histórico de PRs
1. Multi-select filters + dashed lines + tooltips
2. Competitive analysis
3. Interactive tooltips
4. PWA (manifest, sw.js, icons)
5. Fix PWA icons (correct Royal FIC branding colors)
6. Rearview competitive analysis perspective
7. Product/segment evolution in rearview
8. Highlights section
9. Fix highlights visibility
10. Redesign analysis as "Inteligência de Mercado"
11. Remove redundancies, add growth dynamics
12. Separate tables, dividers, reduce color noise
13. Nationwide data (27 UFs) + UF filter

## Ecossistema de Apps SP (repo Vendedores)
Três apps PWA no mesmo repo `sandroregal/Vendedores`, mesmo origin (compartilham IndexedDB):

### 1. Copiloto Comercial SP (`index.html`)
- Fases: Conquista, Retomada, Cross-sell, Pacing
- Base histórica: `historico_SP.json` → IndexedDB `copilotoSP`
- Tab bar fixa inferior com navegação entre apps (🧭📊📅)

### 2. Pacing Vendedores SP (`pacing.html`)
- Acompanhamento diário de vendas vs meta por vendedor
- Fonte: YVIEWCOPA (CSV exportado do SAP)
- **Colunas do YVIEWCOPA (0-indexed):**
  - c[6] = Data de lançamento
  - c[7] = Artigo (código do produto)
  - c[9] = **Denominação = NOME DO VENDEDOR** (descoberta chave)
  - c[16] = Escritório de vendas
  - c[21] = Grupo de preço = código do SUPERVISOR (03, 08, 01, 02, 05) — NÃO é vendedor
  - c[23] = Denominação_2 = nome da BANDEIRA (segmento)
  - c[24] = Qtd.vendas (volume)
  - c[49] = ID parceiro (código do cliente)
- **Escritórios SP:** FI09, FI10, FI13, FI22, FI27
- **"Mesa Regional SP"** = volume de gestão/mesa, excluído do pacing individual (~40k m³)
- **Segmentos (classifySeg):** Bandeira Branca, Consumidor Final, Bandeirado, Usinas, TRR, Congênere
- **Produtos (artFam):** S10 (146-148), S500 (140-141), Gasolina (101-103), Hidratado (109)
- 4 abas: Volume (ordena por vol realizado), Clientes (por nº cli), Produtos, Análise (consolidada do time)
- Não depende do EMB/IndexedDB — lê vendedor direto do CSV c[9]
- PWA: `manifest-pacing.webmanifest`, SW compartilhado (`sw.js`)

### 3. Mes-Corrente (`sandroregal/Mes-Corrente/`)
- Repo separado, mesmo YVIEWCOPA como fonte
- URL: `sandroregal.github.io/Mes-Corrente/`

### Navegação entre Apps
- Barra de ícones compacta (🧭 Copiloto · 📊 Pacing · 📅 Mês)
- App atual fica opaco/desabilitado, outros são links
- No Copiloto: ícones ficam na nav fixa inferior (acima dos botões de fase)
- No Pacing e Mes-Corrente: ícones ficam no rodapé
- URLs case-sensitive: `/Vendedores/`, `/Mes-Corrente/` (maiúsculas importam no GitHub Pages)

## Cache do Service Worker
Ao atualizar o app, o usuário pode precisar:
- Fechar e reabrir o app (PWA)
- Hard refresh no navegador (Ctrl+Shift+R)
- O SW usa network-first, então após 2 reloads a versão nova aparece
