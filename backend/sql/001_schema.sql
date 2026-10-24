CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE users (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    apple_subject text NOT NULL UNIQUE,
    account_created_at timestamptz NOT NULL DEFAULT now(),
    deleted_at timestamptz
);

CREATE TABLE private_drafts (
    id uuid NOT NULL,
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    content jsonb NOT NULL,
    image_object_key text,
    created_at timestamptz NOT NULL DEFAULT now(),
    updated_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, id)
);

CREATE TABLE community_assets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    author_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    title text NOT NULL CHECK (length(title) BETWEEN 1 AND 80),
    description text NOT NULL CHECK (length(description) <= 240),
    category text NOT NULL CHECK (
        category IN ('Minimalista', 'Abstracto', 'Neón', 'Elegante',
                     'Retro', 'Naturaleza', 'Arte', 'Tecnología')
    ),
    tags text[] NOT NULL DEFAULT '{}',
    dominant_colors text[] NOT NULL DEFAULT '{}',
    license text NOT NULL CHECK (license IN ('CC0 1.0', 'CC BY 4.0')),
    rights_confirmed boolean NOT NULL CHECK (rights_confirmed),
    object_key text NOT NULL,
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'approved', 'hidden', 'rejected')),
    use_count integer NOT NULL DEFAULT 0 CHECK (use_count >= 0),
    created_at timestamptz NOT NULL DEFAULT now(),
    moderated_at timestamptz
);

CREATE INDEX community_assets_browse_idx
    ON community_assets (status, created_at DESC);
CREATE INDEX community_assets_category_idx
    ON community_assets (category, status, use_count DESC);

CREATE TABLE favorites (
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    asset_id uuid NOT NULL REFERENCES community_assets(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, asset_id)
);

CREATE TABLE blocked_users (
    blocker_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);

CREATE TABLE content_reports (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    asset_id uuid NOT NULL REFERENCES community_assets(id) ON DELETE CASCADE,
    reason text NOT NULL CHECK (reason IN ('illegal', 'offensive', 'copyright', 'fraud', 'other')),
    detail text NOT NULL DEFAULT '' CHECK (length(detail) <= 500),
    status text NOT NULL DEFAULT 'pending'
        CHECK (status IN ('pending', 'reviewed', 'actioned', 'dismissed')),
    created_at timestamptz NOT NULL DEFAULT now(),
    moderated_at timestamptz,
    UNIQUE (reporter_id, asset_id)
);

CREATE INDEX content_reports_review_idx
    ON content_reports (status, created_at);

CREATE TABLE issued_passes (
    pass_type_identifier text NOT NULL,
    serial_number text NOT NULL,
    user_id uuid REFERENCES users(id) ON DELETE SET NULL,
    draft_id uuid NOT NULL,
    authentication_token_hash text NOT NULL,
    content jsonb NOT NULL,
    image_object_key text,
    updated_at timestamptz NOT NULL DEFAULT now(),
    update_tag bigint NOT NULL DEFAULT 1,
    revoked_at timestamptz,
    PRIMARY KEY (pass_type_identifier, serial_number)
);

CREATE INDEX issued_passes_user_idx ON issued_passes (user_id, updated_at DESC);

CREATE TABLE wallet_devices (
    device_library_identifier text NOT NULL,
    pass_type_identifier text NOT NULL,
    serial_number text NOT NULL,
    push_token text NOT NULL,
    registered_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (device_library_identifier, pass_type_identifier, serial_number),
    FOREIGN KEY (pass_type_identifier, serial_number)
        REFERENCES issued_passes(pass_type_identifier, serial_number) ON DELETE CASCADE
);

CREATE TABLE rate_limit_buckets (
    user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    action text NOT NULL,
    bucket_start timestamptz NOT NULL,
    uses integer NOT NULL DEFAULT 1,
    PRIMARY KEY (user_id, action, bucket_start)
);
