# Rina Soluções · Gestão de Pagamentos — estado do projeto

Página (protótipo): https://claude.ai/artifact/35nhN4cadkgRyXQfRHRHLs
ADM Master: rinaildo064@gmail.com

## Feito
- Tela 1: Login / Criar conta (15 dias grátis + R$ 21,00/mês) / Termos (texto provisório)
- Tela 2: Dashboard do Cliente do ADM (5 cards, busca, filtros, tabela PC / cards celular, CRUD, comprovantes com logo + nome da empresa)
- Camada `api` mockada em memória (auth + clients), pronta para trocar pelo Supabase
- Tema azul-marinho/dourado, logo, ícones PWA (Android, iOS, Windows)
- supabase_schema.sql (profiles, clientes, pagamentos, view de status, RLS, trigger de admin)

## Próximos passos
1. Tela 3: Clientes dos Clientes (reutilizar ClientsPanel)
2. Painel do ADM Master (view admin_assinantes)
3. Trocar `api` mock por supabase-js (precisa de URL + anon key)
4. Tela de pagamentos (lançar pagamento na tabela pagamentos)
5. Cobrança da assinatura (R$ 21,00/mês) e bloqueio após o teste
6. Termos jurídicos finais
