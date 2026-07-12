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

## Cache do Service Worker
Ao atualizar o app, o usuário pode precisar:
- Fechar e reabrir o app (PWA)
- Hard refresh no navegador (Ctrl+Shift+R)
- O SW usa network-first, então após 2 reloads a versão nova aparece
