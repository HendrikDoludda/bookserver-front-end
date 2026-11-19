import 'package:bookserver/data/catalog_store.dart';

/// Keeps the catalog in memory, where a test can set and read it, and counts the writes.
class MemoryCatalogStore implements CatalogStore {
  StoredCatalog? catalog;
  var writes = 0;

  @override
  Future<StoredCatalog?> read() async => catalog;

  @override
  Future<void> write(StoredCatalog catalog) async {
    this.catalog = catalog;
    writes++;
  }
}
