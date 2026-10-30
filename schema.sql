-- Enable UUID extension
create extension if not exists "uuid-ossp";

-- 1. PROFILES (Extends Auth)
create table profiles (
  id uuid references auth.users on delete cascade primary key,
  email text,
  full_name text,
  role text default 'manager', -- 'manager', 'viewer'
  avatar_url text,
  created_at timestamp with time zone default timezone('utc'::text, now())
);

-- 2. UNITS (Standardizing measurements)
create table units (
  id uuid default uuid_generate_v4() primary key,
  name text not null, -- e.g., 'Piece', 'Box', 'Liter', 'Milliliter'
  symbol text not null -- e.g., 'pcs', 'bx', 'L', 'ml'
);

-- 3. CATEGORIES (Enforcing Logic Types)
create type inventory_type as enum ('reagent', 'consumable', 'general');

create table categories (
  id uuid default uuid_generate_v4() primary key,
  name text not null,
  type inventory_type not null,
  description text,
  created_at timestamp with time zone default timezone('utc'::text, now())
);

-- 4. ITEMS ( Core Inventory)
create table items (
  id uuid default uuid_generate_v4() primary key,
  organization_id uuid references auth.users(id), -- Optional for multi-tenant future
  category_id uuid references categories(id),
  name text not null,
  barcode text unique,
  
  -- Quantity Tracking
  current_stock numeric default 0,
  min_stock_alert numeric default 10,
  
  -- Unit Conversion Logic
  base_unit_id uuid references units(id), -- e.g., 'Piece'
  purchase_unit_id uuid references units(id), -- e.g., 'Box'
  conversion_rate numeric default 1, -- How many Base Units in a Purchase Unit? (e.g., 100 pcs in 1 Box)
  
  -- Type A: Reagents Specifics
  storage_temp text, -- e.g., '-20C'
  volume_per_unit numeric, -- e.g., 500 (ml)
  volume_unit_id uuid references units(id),

  -- Type B: Consumables Specifics (Dimensions)
  dimensions text, 

  created_at timestamp with time zone default timezone('utc'::text, now())
);

-- 5. BATCHES (For Expiry/Lot Tracking - Critical for Type A)
create table batches (
  id uuid default uuid_generate_v4() primary key,
  item_id uuid references items(id) on delete cascade,
  batch_number text not null,
  expiry_date date, -- CRITICAL for Type A
  sterility_date date, -- CRITICAL for Type B
  quantity numeric default 0,
  created_at timestamp with time zone default timezone('utc'::text, now())
);

-- 6. TRANSACTIONS (Audit Log)
create table transactions (
  id uuid default uuid_generate_v4() primary key,
  item_id uuid references items(id),
  user_id uuid references auth.users(id),
  type text check (type in ('in', 'out', 'adjustment')),
  quantity numeric not null,
  batch_id uuid references batches(id), -- Optional, if specific batch used
  notes text,
  created_at timestamp with time zone default timezone('utc'::text, now())
);
