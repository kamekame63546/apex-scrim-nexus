-- APEX ORACLE Supabase schema draft
-- SAFETY: This script only creates new objects. It does not delete or overwrite existing local data.
-- Review workspace membership/auth policy before production use.

create extension if not exists pgcrypto;

create table if not exists public.workspaces (
  id uuid primary key default gen_random_uuid(),
  workspace_key text not null unique,
  name text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.workspace_members (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin','coach','player','guest')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (workspace_id, user_id)
);

create table if not exists public.scrims (
  id text primary key,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  split_id text,
  scrim_type text not null default 'normal' check (scrim_type in ('normal','poland')),
  scrim_date date,
  block text,
  source_scrim_id text,
  payload jsonb not null,
  content_hash text,
  source_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists scrims_workspace_idx on public.scrims(workspace_id);
create index if not exists scrims_workspace_date_idx on public.scrims(workspace_id, scrim_date desc);
create index if not exists scrims_split_idx on public.scrims(workspace_id, split_id);
create index if not exists scrims_payload_gin_idx on public.scrims using gin(payload);

create table if not exists public.fight_matches (
  id text primary key,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  split_id text,
  match_date date,
  block text,
  match_number integer,
  payload jsonb not null,
  content_hash text,
  source_updated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists fight_matches_workspace_idx on public.fight_matches(workspace_id);
create index if not exists fight_matches_date_idx on public.fight_matches(workspace_id, match_date desc);
create index if not exists fight_matches_payload_gin_idx on public.fight_matches using gin(payload);

create table if not exists public.final_zones (
  id text primary key,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  split_id text,
  match_date date,
  block text,
  match_number integer,
  map_id text,
  payload jsonb not null,
  content_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists final_zones_workspace_idx on public.final_zones(workspace_id);
create index if not exists final_zones_lookup_idx on public.final_zones(workspace_id, split_id, map_id, match_date desc);

create table if not exists public.ring_console (
  id text primary key,
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  split_id text,
  map_id text,
  poi_id text,
  phase text,
  payload jsonb not null,
  content_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create index if not exists ring_console_lookup_idx
  on public.ring_console(workspace_id, split_id, map_id, poi_id);

create table if not exists public.master_data (
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  category text not null,
  item_id text not null,
  payload jsonb not null,
  content_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  primary key (workspace_id, category, item_id)
);

create index if not exists master_data_category_idx
  on public.master_data(workspace_id, category);

create table if not exists public.sync_migrations (
  id uuid primary key default gen_random_uuid(),
  workspace_id uuid not null references public.workspaces(id) on delete cascade,
  migration_name text not null,
  source_name text not null,
  source_count integer not null default 0,
  destination_count integer not null default 0,
  source_hash text,
  destination_hash text,
  status text not null check (status in ('planned','copied','verified','failed','rolled_back')),
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  verified_at timestamptz
);

-- updated_at helper
create or replace function public.apex_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists trg_workspaces_updated_at on public.workspaces;
create trigger trg_workspaces_updated_at
before update on public.workspaces
for each row execute function public.apex_set_updated_at();

drop trigger if exists trg_workspace_members_updated_at on public.workspace_members;
create trigger trg_workspace_members_updated_at
before update on public.workspace_members
for each row execute function public.apex_set_updated_at();

drop trigger if exists trg_scrims_updated_at on public.scrims;
create trigger trg_scrims_updated_at
before update on public.scrims
for each row execute function public.apex_set_updated_at();

drop trigger if exists trg_fight_matches_updated_at on public.fight_matches;
create trigger trg_fight_matches_updated_at
before update on public.fight_matches
for each row execute function public.apex_set_updated_at();

drop trigger if exists trg_final_zones_updated_at on public.final_zones;
create trigger trg_final_zones_updated_at
before update on public.final_zones
for each row execute function public.apex_set_updated_at();

drop trigger if exists trg_ring_console_updated_at on public.ring_console;
create trigger trg_ring_console_updated_at
before update on public.ring_console
for each row execute function public.apex_set_updated_at();

drop trigger if exists trg_master_data_updated_at on public.master_data;
create trigger trg_master_data_updated_at
before update on public.master_data
for each row execute function public.apex_set_updated_at();

-- RLS
alter table public.workspaces enable row level security;
alter table public.workspace_members enable row level security;
alter table public.scrims enable row level security;
alter table public.fight_matches enable row level security;
alter table public.final_zones enable row level security;
alter table public.ring_console enable row level security;
alter table public.master_data enable row level security;
alter table public.sync_migrations enable row level security;

create or replace function public.apex_is_workspace_member(target_workspace uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.workspace_members wm
    where wm.workspace_id = target_workspace
      and wm.user_id = auth.uid()
      and wm.is_active = true
  );
$$;

create or replace function public.apex_can_edit_workspace(target_workspace uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.workspace_members wm
    where wm.workspace_id = target_workspace
      and wm.user_id = auth.uid()
      and wm.is_active = true
      and wm.role in ('admin','coach')
  );
$$;

-- Read policies
create policy "workspace members read scrims"
on public.scrims for select
using (public.apex_is_workspace_member(workspace_id));

create policy "workspace members read fights"
on public.fight_matches for select
using (public.apex_is_workspace_member(workspace_id));

create policy "workspace members read final zones"
on public.final_zones for select
using (public.apex_is_workspace_member(workspace_id));

create policy "workspace members read ring console"
on public.ring_console for select
using (public.apex_is_workspace_member(workspace_id));

create policy "workspace members read master data"
on public.master_data for select
using (public.apex_is_workspace_member(workspace_id));

-- Edit policies: admin/coach only
create policy "editors insert scrims"
on public.scrims for insert
with check (public.apex_can_edit_workspace(workspace_id));

create policy "editors update scrims"
on public.scrims for update
using (public.apex_can_edit_workspace(workspace_id))
with check (public.apex_can_edit_workspace(workspace_id));

create policy "editors insert fights"
on public.fight_matches for insert
with check (public.apex_can_edit_workspace(workspace_id));

create policy "editors update fights"
on public.fight_matches for update
using (public.apex_can_edit_workspace(workspace_id))
with check (public.apex_can_edit_workspace(workspace_id));

create policy "editors insert final zones"
on public.final_zones for insert
with check (public.apex_can_edit_workspace(workspace_id));

create policy "editors update final zones"
on public.final_zones for update
using (public.apex_can_edit_workspace(workspace_id))
with check (public.apex_can_edit_workspace(workspace_id));

create policy "editors insert ring console"
on public.ring_console for insert
with check (public.apex_can_edit_workspace(workspace_id));

create policy "editors update ring console"
on public.ring_console for update
using (public.apex_can_edit_workspace(workspace_id))
with check (public.apex_can_edit_workspace(workspace_id));

create policy "editors insert master data"
on public.master_data for insert
with check (public.apex_can_edit_workspace(workspace_id));

create policy "editors update master data"
on public.master_data for update
using (public.apex_can_edit_workspace(workspace_id))
with check (public.apex_can_edit_workspace(workspace_id));

-- Realtime publication: run only after RLS and migration verification.
-- alter publication supabase_realtime add table
--   public.scrims,
--   public.fight_matches,
--   public.final_zones,
--   public.ring_console,
--   public.master_data;
