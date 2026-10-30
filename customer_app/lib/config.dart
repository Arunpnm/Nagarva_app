/// The one Supabase project both Nagarva apps use. The anon key is public
/// by design (it is in every web build); row-level security decides what it
/// can do. The customer app may read cities, the catalogue and prices, and
/// ask mkt_quote() for a price; nothing else.
const kSupabaseUrl = 'https://hqqcapifefsaqvotqvlt.supabase.co';
const kSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhxcWNhcGlmZWZzYXF2b3Rxdmx0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1MjMwNjksImV4cCI6MjA5NTA5OTA2OX0.Z_nkIvupu-zMnxOWT2n_8wUwTH4Kb3K8nOnvs1wkCbY';

/// Booking stays off until online payment is chosen (Arun, 30 Oct 2026:
/// "wait for the gateway"; CLAUDE.md Item 31). The whole flow and the
/// price work; the last button says payments open soon instead of taking
/// money or creating a job.
const kBookingLive = false;
