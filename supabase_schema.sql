-- =====================================================================
-- Rina Soluções · Gestão de Pagamentos · Schema Supabase
-- Cole no SQL Editor do Supabase e execute de uma vez.
-- =====================================================================

-- 1) PERFIS (Nível 2: assinantes; Nível 1: is_admin = true) ------------
create table public.profiles (
  id              uuid primary key references auth.users(id) on delete cascade,
  empresa         text not null,                       -- nome que aparece nos comprovantes
  email           text,
  telefone        text,
  is_admin        boolean not null default false,      -- ADM Master
  plano_status    text not null default 'teste'
                  check (plano_status in ('teste','ativo','inadimplente','cancelado')),
  trial_ends_at   timestamptz not null default (now() + interval '15 days'),
  plano_valor     numeric(10,2) not null default 21.00,
  aceitou_termos_em timestamptz,
  created_at      timestamptz not null default now()
);

-- 2) CLIENTES (Nível 3: clientes dos assinantes) -----------------------
create table public.clientes (
  id              bigint generated always as identity primary key,
  owner_id        uuid not null references public.profiles(id) on delete cascade,
  nome            text not null,
  contato         text,
  data_inicial    date not null default current_date,
  vencimento      date not null,
  valor           numeric(12,2) not null check (valor >= 0),
  pago            numeric(12,2) not null default 0 check (pago >= 0),  -- mantido por trigger
  tipo            text not null default 'Fixo' check (tipo in ('Fixo','Variável')),
  created_at      timestamptz not null default now()
);
create index clientes_owner_idx on public.clientes(owner_id);
create index clientes_venc_idx  on public.clientes(owner_id, vencimento);

-- 3) PAGAMENTOS (histórico; base dos comprovantes) ---------------------
create table public.pagamentos (
  id          bigint generated always as identity primary key,
  owner_id    uuid not null references public.profiles(id) on delete cascade,
  cliente_id  bigint not null references public.clientes(id) on delete cascade,
  valor       numeric(12,2) not null check (valor > 0),
  pago_em     date not null default current_date,
  observacao  text,
  created_at  timestamptz not null default now()
);
create index pagamentos_cliente_idx on public.pagamentos(cliente_id);

-- 4) VIEW com saldo e status calculados (o front usa esta view) --------
create view public.clientes_status
with (security_invoker = true) as
select c.*,
       (c.valor - c.pago) as saldo,
       case when c.valor - c.pago <= 0        then 'quitado'
            when c.vencimento < current_date  then 'atrasado'
            else 'em_dia' end as status
from public.clientes c;

-- 5) TRIGGERS ----------------------------------------------------------
-- 5a) Cria o perfil automaticamente no cadastro.
--     No front: supabase.auth.signUp({email, password,
--       options:{ data:{ empresa: nome } }})
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, empresa, email, aceitou_termos_em, is_admin)
  values (new.id,
          coalesce(new.raw_user_meta_data->>'empresa', split_part(new.email,'@',1)),
          new.email, now(),
          lower(new.email) = 'rinaildo064@gmail.com');   -- ADM Master
  return new;
end $$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

-- 5b) Mantém clientes.pago = soma dos pagamentos.
create or replace function public.sync_pago()
returns trigger language plpgsql security definer set search_path = public as $$
declare cid bigint := coalesce(new.cliente_id, old.cliente_id);
begin
  update public.clientes
     set pago = coalesce((select sum(valor) from public.pagamentos where cliente_id = cid), 0)
   where id = cid;
  return null;
end $$;

create trigger pagamentos_sync
after insert or update or delete on public.pagamentos
for each row execute function public.sync_pago();

-- 6) FUNÇÕES AUXILIARES ------------------------------------------------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false)
$$;

-- Assinatura ativa (teste vigente ou plano ativo)? Use nas policies de escrita.
create or replace function public.assinatura_ok()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles p
                 where p.id = auth.uid()
                   and (p.plano_status = 'ativo'
                        or (p.plano_status = 'teste' and p.trial_ends_at > now())))
$$;

-- 7) ROW LEVEL SECURITY ------------------------------------------------
alter table public.profiles   enable row level security;
alter table public.clientes   enable row level security;
alter table public.pagamentos enable row level security;

-- profiles: cada um vê/edita o próprio; ADM Master vê tudo.
create policy "perfil: ler" on public.profiles for select
  using (id = auth.uid() or public.is_admin());
create policy "perfil: editar proprio" on public.profiles for update
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

-- Impede o assinante de se promover a admin ou mexer no plano pelo front.
create or replace function public.protect_profile_fields()
returns trigger language plpgsql as $$
begin
  if not public.is_admin() then
    new.is_admin := old.is_admin;
    new.plano_status := old.plano_status;
    new.trial_ends_at := old.trial_ends_at;
    new.plano_valor := old.plano_valor;
  end if;
  return new;
end $$;
create trigger profiles_protect before update on public.profiles
for each row execute function public.protect_profile_fields();

-- clientes: o dono lê sempre; escreve só com assinatura em dia; ADM lê tudo.
create policy "clientes: ler" on public.clientes for select
  using (owner_id = auth.uid() or public.is_admin());
create policy "clientes: inserir" on public.clientes for insert
  with check (owner_id = auth.uid() and public.assinatura_ok());
create policy "clientes: editar" on public.clientes for update
  using (owner_id = auth.uid() and public.assinatura_ok());
create policy "clientes: excluir" on public.clientes for delete
  using (owner_id = auth.uid() and public.assinatura_ok());

-- pagamentos: mesma regra.
create policy "pagamentos: ler" on public.pagamentos for select
  using (owner_id = auth.uid() or public.is_admin());
create policy "pagamentos: inserir" on public.pagamentos for insert
  with check (owner_id = auth.uid() and public.assinatura_ok()
              and exists (select 1 from public.clientes c
                          where c.id = cliente_id and c.owner_id = auth.uid()));
create policy "pagamentos: excluir" on public.pagamentos for delete
  using (owner_id = auth.uid() and public.assinatura_ok());

-- 8) VISÃO DO ADM MASTER (painel de assinantes) ------------------------
create view public.admin_assinantes
with (security_invoker = true) as
select p.id, p.empresa, p.email, p.plano_status, p.trial_ends_at, p.created_at,
       (select count(*) from public.clientes c where c.owner_id = p.id) as total_clientes
from public.profiles p
where public.is_admin();

-- 9) ADM MASTER: rinaildo064@gmail.com ---------
-- (já automático pelo trigger acima; este comando cobre conta criada antes do SQL)
update public.profiles set is_admin = true where lower(email) = 'rinaildo064@gmail.com';
