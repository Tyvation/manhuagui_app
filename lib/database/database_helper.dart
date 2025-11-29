import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/favorite_comic.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'manhuagui.db');
    return await openDatabase(
      path,
      version: 4,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE favorites(
        id TEXT PRIMARY KEY,
        title TEXT,
        cover TEXT,
        url TEXT,
        latest_chapter TEXT,
        page TEXT,
        last_read TEXT,
        genres TEXT,
        chapter_titles TEXT,
        chapter_count INTEGER,
        is_finished INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Add chapter_titles column to favorites table
      await db.execute('ALTER TABLE favorites ADD COLUMN chapter_titles TEXT');

      // Drop unused tables if they exist
      await db.execute('DROP TABLE IF EXISTS chapter_cache');
      await db.execute('DROP TABLE IF EXISTS comic_progress');
    }

    if (oldVersion < 3) {
      // Add chapter_count column to favorites table
      await db.execute(
          'ALTER TABLE favorites ADD COLUMN chapter_count INTEGER DEFAULT 0');
    }

    if (oldVersion < 4) {
      // Add is_finished column to favorites table
      await db.execute(
          'ALTER TABLE favorites ADD COLUMN is_finished INTEGER DEFAULT 0');
    }
  }

  // Favorites CRUD
  Future<int> insertFavorite(FavoriteComic comic) async {
    Database db = await database;
    return await db.insert('favorites', comic.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<FavoriteComic>> getFavorites() async {
    Database db = await database;
    final List<Map<String, dynamic>> maps = await db.query('favorites');
    return List.generate(maps.length, (i) {
      return FavoriteComic.fromMap(maps[i]);
    });
  }

  Future<void> updateFavorite(FavoriteComic comic) async {
    Database db = await database;
    await db.update(
      'favorites',
      comic.toMap(),
      where: 'id = ?',
      whereArgs: [comic.id],
    );
  }

  Future<void> deleteFavorite(String id) async {
    Database db = await database;
    await db.delete(
      'favorites',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<FavoriteComic?> getFavorite(String id) async {
    Database db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      'favorites',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isNotEmpty) {
      return FavoriteComic.fromMap(maps.first);
    }
    return null;
  }
}
