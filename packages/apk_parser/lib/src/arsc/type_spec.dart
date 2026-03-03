import 'resource_value.dart';

class TypeSpec {
  final int id;
  final String name;
  final List<int> entryFlags;
  final List<TypeConfig> configs;

  TypeSpec({
    required this.id,
    required this.name,
    required this.entryFlags,
    required this.configs,
  });
}

class TypeConfig {
  final ResourceConfig config;
  final Map<int, ResourceEntry> entries;

  TypeConfig({required this.config, required this.entries});
}
