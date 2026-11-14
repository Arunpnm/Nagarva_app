/// The one Supabase project both Nagarva apps use. The anon key is public
/// by design (it is in every web build); row-level security decides what it
/// can do. The customer app may read cities, the catalogue and prices, and
/// ask mkt_quote() for a price; nothing else.
const kSupabaseUrl = 'https://hqqcapifefsaqvotqvlt.supabase.co';
const kSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImhxcWNhcGlmZWZzYXF2b3Rxdmx0Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzk1MjMwNjksImV4cCI6MjA5NTA5OTA2OX0.Z_nkIvupu-zMnxOWT2n_8wUwTH4Kb3K8nOnvs1wkCbY';

/// Booking with online payment (Razorpay payment links through the
/// mkt-book function; Arun, 14 Nov 2026). Test keys in Supabase give test
/// payments. Set false to go back to quote-only: the last button then says
/// payments open soon.
const kBookingLive = true;
