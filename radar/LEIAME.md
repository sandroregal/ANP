# Radar · Comercial SP (Royal FIC)

App de celular para atualizar as atividades e projetos do Comercial SP direto na planilha
"Agente de Rotina — Painel da Semana". O dashboard e os check-ins diários leem a mesma planilha.

Endereço: https://sandroregal.github.io/ANP/radar/

## Instalação (uma vez, cerca de 5 minutos)

1. Abra a planilha no computador > **Extensões > Apps Script**.
2. Apague o conteúdo e cole o arquivo `apps-script/Code.gs` desta pasta. Salve.
3. **Configurações do projeto** (engrenagem) > **Propriedades do script** > adicionar:
   `TOKEN` = uma senha longa só sua.
4. **Implantar > Nova implantação** > tipo **App da Web**.
   Executar como: **Eu**. Quem pode acessar: **Qualquer pessoa**. Autorize.
5. Copie a URL que termina em `/exec`.
6. No celular, abra o endereço do app, toque em ⚙ e cole a URL e o TOKEN.
   Para usar como app: menu do navegador > **Adicionar à tela inicial**.

## Uso

- Filtros: No radar, Para revisar, Fora do radar, Concluídos, Todos.
- Botões rápidos no cartão: Concluir, No radar / Fora do radar, Revisar.
- Toque no cartão para editar atividade, prazo, situação, prioridade, próximo passo e incluir anotação datada.
- **+ Nova** cria uma atividade (ID automático).

## Segurança

- Nenhum dado fica no GitHub: o app só mostra o que vem da planilha, com o TOKEN.
- URL e TOKEN ficam salvos apenas no aparelho.
- Para trocar a senha: altere o TOKEN nas propriedades do script e no ⚙ do app.
- Ao alterar o `Code.gs`, use **Implantar > Gerenciar implantações > Editar > Nova versão** para manter a mesma URL.
