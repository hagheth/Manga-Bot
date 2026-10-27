"""
Run this once to create the manga table in Supabase.
The SQL below should be pasted into Supabase SQL Editor.
"""

SQL = """
create table if not exists manga (
    id bigint generated always as identity primary key,
    user_id bigint not null,
    title text not null,
    url text,
    chapter int default 0,
    status text default 'reading' check (status in ('reading', 'completed', 'on_hold', 'dropped')),
    notes text,
    created_at timestamptz default now(),
    updated_at timestamptz default now()
);

-- Index for fast lookup per user
create index if not exists manga_user_id_idx on manga(user_id);
"""

print("Copy and paste this SQL into your Supabase SQL Editor:")
print("https://supabase.com/dashboard/project/yqfofbivqzoxkqrritqq/sql/new")
print()
print(SQL)
