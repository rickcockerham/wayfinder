# Wayfinder Time Manager
## A project management app for INTP people

A tiny Rails app to help you decide **what to do today**.

I’ve tried Post-its, spreadsheets, heroic Kanbans, and eleven different apps. One afternoon I literally screamed at my to-do list: “I’m not in the mood for that. I know it’s important. Still no!” The list did not care. Most tools assume “priority” is one magic number and that I’m a robot. I’m not.

Wayfinder lets you filter by mood, category, and time on hand—as in “desk-mood” vs. “sawdust-mood,” not just generic tags. It scores projects by impacts (personal, emotional, family) with a deadline nudge, so something that matters a lot to my partner can outrank something that’s only important to me.

Dependencies actually matter here. If a project is blocked, it won’t be suggested—and the blocker inherits the highest score of anything it blocks. If B is blocking critical A, then B jumps to the top so you stop skipping over it.

Recurring work comes in **two!!** flavors:

Fixed schedule (like everyone else): every N days/weeks/months, the 1st of the month, or a specific date (e.g., July 1).

**After completion**: next due date is N units after you actually finish.  Because if you were two months late changing the furnace filter, scheduling another change next week is… dumb.

It also tracks materials vs. inventory, builds a shopping list by vendor, and remembers where you put things—because Future You will definitely forget.

---

## Features

* **Tasks (“Items”)**

  * Title, notes, category, mood
  * Impacts (personal / emotional / family), time estimate, cost, deadline, done
  * Parent/child relationships (for outlining)
  * **Blockers**: “B blocks A” = A won’t be suggested until B is done
* **Scoring & Order**

  * Importance = impacts + deadline (overdue priority) + time-fit
  * **Max-cascade**: a blocker inherits the **max** importance of any blocked descendant
    → If A is critical but blocked by B, **B floats to the top** and A nests under B
  * Listing shows **blockers followed by their blocked items**
* **Materials & Inventory**

  * Each item can list **material requirements** (name, qty, unit, default shop)
  * Global **inventory** with qty, unit, location, default shop
  * Item page shows what’s **missing** vs. your inventory
  * **Shopping list** by shop, grouped by project; check items off to add to inventory
  * When an item is **completed**, inventory is **consumed** automatically; deficits are reported
* **Home page picker**

  * Top 5 items by default; “show more” (10/20/30)
  * Filters: moods (checkboxes), category (select), time commitment (slider)
  * Sort: by importance (default) or by time
  * Filters are **collapsed** by default; “Filters” button toggles
* **Recurring items**

  * Two recurrence types:

    1. **Fixed schedule** (next = scheduled deadline + frequency)
    2. **After completion** (next = completion date + frequency)
  * Frequencies: every N days/weeks/months/years; 1st of month; specific date (e.g., Oct 17)
  * On completion, the next item is auto-created with the next deadline
* **Notes (WYSIWYG)**

  * Quill editor (CDN) for `notes`, HTML sanitized on render
* **Simple auth**

  * One **access key** (env/credentials). Sign in once per browser → long-lived signed cookie
* **Dark sci-fi theme**

  * Single stylesheet; links rendered as soft, **iridescent “stones”** ✨

---

## Data model (high level)

* `Item`

  * `title`, `notes`, `category_id`, `mood_id`
  * `personal_impact`, `emotional_impact`, `family_impact`
  * `time_estimate_minutes`, `cost_cents`, `deadline`, `done`, `completed_at`
  * **Recurrence**: `recurrence_kind`, `recurrence_unit`, `recurrence_interval`, `recurrence_day_of_month`, `recurrence_month_of_year`, `recurrence_start_on`
  * Associations:

    * `belongs_to :parent` / `has_many :children`
    * `has_many :blocking_edges` / `has_many :blockers, through: :blocking_edges`
    * `has_many :blocked_edges`  / `has_many :blocks, through: :blocked_edges`
    * `has_many :material_requirements`
* `ItemBlock` (join: blocker → blocked)
* `MaterialRequirement` (per item; name, qty\_needed, unit, **shop\_id**)
* `InventoryItem` (name, qty\_have, unit, location, **shop\_id**)
* Lookup tables: `categories`, `moods`, `shops`, `locations` (enums moved to tables)

> When an item is marked **done**, inventories are decremented (via `ItemCompletion`), deficits are reported, and the **next recurring** item is created (if applicable) via `RecurrenceGenerator`.

---

## Importance & ordering

* **Base importance** (simplified):
  `impacts + overdue factor + time-fit bonus`
* **Max-cascade**: a blocker’s displayed score becomes `max(own_base, max(descendants))`
* **Display order**: roots by importance, then **each blocker followed by its blocked items** (sorted by importance). Items appear **once** (if multiple blockers, they nest under the highest-score blocker).

---

## Quick start (local dev)

**Prereqs**

* Ruby **3.2.x** (rbenv recommended)
* MySQL server + client dev headers (`libmysqlclient-dev`)
* Git

**Ubuntu setup**

```bash
sudo apt update
sudo apt install -y build-essential git curl pkg-config libmysqlclient-dev mysql-server

# rbenv (per user)
git clone https://github.com/rbenv/rbenv.git ~/.rbenv
echo 'export PATH="$HOME/.rbenv/bin:$PATH"' >> ~/.bashrc
echo 'eval "$(rbenv init - bash)"' >> ~/.bashrc
exec $SHELL -l
git clone https://github.com/rbenv/ruby-build.git ~/.rbenv/plugins/ruby-build
rbenv install 3.2.2
rbenv global 3.2.2
gem install bundler
```

**Clone & install**

```bash
git clone https://github.com/rickcockerham/wayfinder.git
cd wayfinder
bundle install
bin/rails db:setup   # or: db:create db:migrate
```

**Simple auth key (optional in dev)**

```bash
# Either credentials…
bin/rails secret   # copy this
bin/rails credentials:edit
# wayfinder:
#   access_token: PASTE_THE_SECRET

# …or env var
export WAYFINDER_ACCESS_TOKEN=PASTE_THE_SECRET
```

**Run**

```bash
bin/rails s
# http://localhost:3000
# First visit: /login?key=PASTE_THE_SECRET  (sets a signed cookie)
```

---

## Production (notes)

* App server: Puma; optional Nginx reverse proxy (HTTP or HTTPS)
* Secrets:

  * `RAILS_MASTER_KEY` (to decrypt credentials) **or** provide `SECRET_KEY_BASE`
  * `WAYFINDER_ACCESS_TOKEN` (for simple auth)
* DB: set up `config/database.yml` or `DATABASE_URL`

Minimal systemd service example:

```ini
[Service]
User=deploy
WorkingDirectory=/var/www/wayfinder
Environment=RAILS_ENV=production
Environment=RAILS_MASTER_KEY=YOUR_KEY
Environment=PATH=/home/deploy/.rbenv/shims:/home/deploy/.rbenv/bin:/usr/bin
ExecStart=/home/deploy/.rbenv/shims/bundle exec puma -C config/puma.rb -b tcp://127.0.0.1:3000
Restart=always
```

Nginx (HTTP → Puma 3000):

```nginx
server {
  listen 80;
  server_name _;

  location / {
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto http;
    proxy_pass http://127.0.0.1:3000;
  }
}
```

---

## Usage tips

### Bulk import (fast capture)

Paste multiple items (one per line) in **Items → Bulk paste**:

```
Title | category=shop | mood=work | pi=3 ei=2 fi=1 | t=120 | cost=50 | deadline=2025-09-01 | materials="screws:50 pcs; plywood:1 sheet"
```

Shorthand:

* `pi/ei/fi` → impacts
* `t` → minutes
* `materials` → `name:qty unit; name:qty unit; …`

### Materials & shopping

* Each item has a **Materials** link → a paged list of all materials with a quick search
* Add 1–3 new material lines at the top; check existing rows with a **non-zero qty** to attach
* Choose a **shop** per material; the **Shopping List** page groups by shop & project
* Check an item on the shopping list → it’s **added to inventory**

### Completion flow

* Mark an item **Done**:

  1. Inventory **consumption** happens (deficits reported)
  2. If the item is **recurring**, the next item is **created** with the new deadline

### Notes editor

* The item form/show uses **Quill**; HTML is sanitized on display
* You can paste links, lists, and code blocks

---

## Configuration

Environment / credentials you may set:

* `wayfinder.access_token` (credentials) or `WAYFINDER_ACCESS_TOKEN` (env)
  → enables **simple auth**; sign in via `/login?key=…`
* `SECRET_KEY_BASE` (or use encrypted credentials + `RAILS_MASTER_KEY`)
* Database config in `config/database.yml` or `DATABASE_URL`

---

## Styling

Dark theme lives in `app/assets/stylesheets/wayfinder_dark.css`.
Tweak the top‐level CSS variables to adjust colors:

```css
:root {
  --bg: #0c0f14;
  --text: #e6edf3;
  --accent: #6cf0ff;
  --accent-2: #a978ff;
  /* … */
}
```

Links are rendered as soft **iridescent buttons**. 🎛️ Lower the effect by reducing `saturate()` or rim `opacity`.

---

## Security

* Single shared **access key** = simple gate for a personal deployment
* Cookie is **signed** and **HTTP-only**; marked **Secure** in production
* Rotate the key to invalidate all sessions

> Not intended for multi-tenant or public multi-user scenarios without additional auth.

---

## Roadmap / ideas

* Optional email reminders for upcoming deadlines
* Calendar feed (ICS) for deadlines
* Per-item attachments (Active Storage / S3)
* Multi-user roles (if needed)

---

## License

MIT — see `LICENSE` (or choose a different license if you prefer).

---

## Contributing

PRs are welcome. Please keep changes small and focused; include a brief description and, when relevant, a screenshot or GIF.

---

## Troubleshooting

* **MySQL gem fails**: install headers `sudo apt install -y libmysqlclient-dev` and re-bundle.
* **Rails 403 in production**: add your host/IP to `config.hosts` in `production.rb`.
* **Credentials error**: set `RAILS_MASTER_KEY` or create `config/credentials/production.key`.
* **Git push prompts for password**: switch remote to SSH (`git@github.com:rickcockerham/wayfinder.git`) and add your SSH key.

---

Happy making! 🛠️
