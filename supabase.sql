-- CONTROLE DE PERDAS - rode este arquivo inteiro no Supabase (SQL Editor > New query > Run)
create extension if not exists pgcrypto;

create table if not exists motivos(
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  ativo boolean not null default true);

create table if not exists perdas(
  id uuid primary key default gen_random_uuid(),
  criado_em timestamptz not null default now(),
  dia date not null,                      -- dia de referência (3º turno após 21:55 conta para o dia seguinte)
  turno smallint not null check (turno in (1,2,3)),
  motivo_id uuid,
  motivo text not null,
  kg numeric(10,2) not null check (kg > 0),
  responsavel text not null);
create index if not exists perdas_dia_turno on perdas(dia, turno);

create table if not exists acessos(
  perfil text primary key check (perfil in ('admin','1','2','3')),
  senha_hash text not null);

-- Ninguém acessa as tabelas direto: tudo passa pelas funções abaixo (que checam a senha)
alter table motivos enable row level security;
alter table perdas enable row level security;
alter table acessos enable row level security;

-- Senhas iniciais (TROQUE logo no primeiro acesso, na aba Senhas do admin)
insert into acessos(perfil, senha_hash) values
  ('admin', crypt('admin123', gen_salt('bf'))),
  ('1', crypt('1111', gen_salt('bf'))),
  ('2', crypt('2222', gen_salt('bf'))),
  ('3', crypt('3333', gen_salt('bf')))
on conflict (perfil) do nothing;

create or replace function _ok(p_perfil text, p_senha text) returns boolean
language sql security definer set search_path = public, extensions as $$
  select exists(select 1 from acessos where perfil = p_perfil and senha_hash = crypt(p_senha, senha_hash)) $$;
revoke all on function _ok(text, text) from public, anon, authenticated;

create or replace function login(p_perfil text, p_senha text) returns boolean
language sql security definer set search_path = public, extensions as $$ select _ok(p_perfil, p_senha) $$;

-- Dia de referência (horário de Brasília). 3º turno: a partir das 21:55 conta para o dia seguinte.
create or replace function dia_ref(p_turno int) returns date language sql stable as $$
  select case when p_turno = 3 and (now() at time zone 'America/Sao_Paulo')::time >= time '21:55'
              then (now() at time zone 'America/Sao_Paulo')::date + 1
              else (now() at time zone 'America/Sao_Paulo')::date end $$;

create or replace function listar_motivos(p_perfil text, p_senha text)
returns table(id uuid, nome text, ativo boolean)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not _ok(p_perfil, p_senha) then raise exception 'Acesso negado'; end if;
  return query select m.id, m.nome, m.ativo from motivos m where p_perfil = 'admin' or m.ativo order by m.nome;
end $$;

create or replace function lancar_perdas(p_perfil text, p_senha text, p_responsavel text, p_itens jsonb)
returns date language plpgsql security definer set search_path = public, extensions as $$
declare t int; d date;
begin
  if p_perfil not in ('1','2','3') or not _ok(p_perfil, p_senha) then raise exception 'Acesso negado'; end if;
  if coalesce(trim(p_responsavel), '') = '' then raise exception 'Informe o responsável'; end if;
  t := p_perfil::int; d := dia_ref(t);
  insert into perdas(dia, turno, motivo_id, motivo, kg, responsavel)
  select d, t, m.id, m.nome, (i->>'kg')::numeric, trim(p_responsavel)
  from jsonb_array_elements(p_itens) i
  join motivos m on m.id = (i->>'motivo_id')::uuid
  where m.ativo and (i->>'kg')::numeric > 0;
  return d;
end $$;

-- Operador só enxerga o próprio turno (últimos 62 dias); admin enxerga tudo
create or replace function historico(p_perfil text, p_senha text, p_de date, p_ate date)
returns table(id uuid, criado_em timestamptz, dia date, turno smallint, motivo text, kg numeric, responsavel text)
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not _ok(p_perfil, p_senha) then raise exception 'Acesso negado'; end if;
  return query
    select p.id, p.criado_em, p.dia, p.turno, p.motivo, p.kg, p.responsavel
    from perdas p
    where p.dia between p_de and p_ate
      and (p_perfil = 'admin' or (p.turno = p_perfil::int and p.dia >= current_date - 62))
    order by p.criado_em desc;
end $$;

-- Funções só do admin
create or replace function excluir_perda(p_senha text, p_id uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin if not _ok('admin', p_senha) then raise exception 'Acesso negado'; end if;
  delete from perdas where id = p_id; end $$;

create or replace function salvar_motivo(p_senha text, p_nome text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin if not _ok('admin', p_senha) then raise exception 'Acesso negado'; end if;
  insert into motivos(nome) values (trim(p_nome)); end $$;

create or replace function alternar_motivo(p_senha text, p_id uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin if not _ok('admin', p_senha) then raise exception 'Acesso negado'; end if;
  update motivos set ativo = not ativo where id = p_id; end $$;

create or replace function excluir_motivo(p_senha text, p_id uuid) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin if not _ok('admin', p_senha) then raise exception 'Acesso negado'; end if;
  delete from motivos where id = p_id; end $$;

create or replace function trocar_senha(p_senha text, p_perfil_alvo text, p_nova text) returns void
language plpgsql security definer set search_path = public, extensions as $$
begin
  if not _ok('admin', p_senha) then raise exception 'Acesso negado'; end if;
  if length(coalesce(p_nova, '')) < 4 then raise exception 'Senha muito curta (mínimo 4)'; end if;
  update acessos set senha_hash = crypt(p_nova, gen_salt('bf')) where perfil = p_perfil_alvo;
end $$;
