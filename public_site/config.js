// Nagarva public pages — configuration.
// The anon key is safe to expose: every table has RLS on, and these pages
// only call SECURITY DEFINER RPCs that validate the token server-side.
window.NAGARVA_CONFIG = {
  SUPABASE_URL: "https://hqqcapifefsaqvotqvlt.supabase.co",
  SUPABASE_ANON_KEY: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhxcWNhcGlmZWZzYXF2b3Rxdmx0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1MjMwNjksImV4cCI6MjA5NTA5OTA2OX0.Z_nkIvupu-zMnxOWT2n_8wUwTH4Kb3K8nOnvs1wkCbY",
};
