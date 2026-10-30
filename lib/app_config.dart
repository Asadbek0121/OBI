class AppConfig {
  static const String supabaseUrl = 'https://tjzqxfisgsxebqalecyj.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRqenF4ZmlzZ3N4ZWJxYWxlY3lqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTMyNzA0MDEsImV4cCI6MjEwODg0NjQwMX0.2n4Yml6NrRUgZxXDM354Ro7QTVH9ZEgVMwb5hKqzUM4';
  static const String geminiApiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
}
