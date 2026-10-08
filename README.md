# Controle de Perdas

Site estático (HTML + JS) com banco no Supabase. Sem build, sem servidor próprio.

## Como publicar
1. **Supabase**: crie um projeto → *SQL Editor* → cole o conteúdo de `supabase.sql` → *Run*.
2. Em *Project Settings → API*, copie a **Project URL** e a **anon public key** e cole no começo do `index.html` (linhas `SUPABASE_URL` e `SUPABASE_ANON_KEY`).
3. **GitHub**: crie um repositório e suba esta pasta (`index.html`, `supabase.sql`, `README.md`).
4. **Vercel**: *Add New → Project* → importe o repositório → *Framework Preset: Other* → Deploy (não precisa de build command).

## Acessos (senhas iniciais — troque no primeiro uso, aba 🔑 SENHAS do admin)
| Acesso | Senha inicial |
|---|---|
| 1º Turno | 1111 |
| 2º Turno | 2222 |
| 3º Turno | 3333 |
| Admin | admin123 |

Cada turno só enxerga e lança no próprio turno. O admin vê tudo.

## Regras
- **Limite de 25 kg** por dia/turno: acima = vermelho, até 25 = verde. Para mudar, edite `LIM` no começo do script do `index.html`.
- **3º turno**: lançamentos a partir das 21:55 contam para o dia seguinte; da meia-noite às 05:30 já caem no próprio dia (função `dia_ref` no SQL, horário de Brasília).
- As tabelas ficam bloqueadas (RLS): o acesso é só pelas funções do banco, que conferem a senha (guardada com hash).
