// ignore_for_file: avoid_print

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() { 
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewExample()
    );
  }
}

class AllowVerticalDragGestureRecognizer extends VerticalDragGestureRecognizer {
  @override
  void rejectGesture(int pointer) {
    acceptGesture(pointer);  //override rejectGesture here
  }
}

class AllowTapGestureRecognizer extends TapGestureRecognizer {
  @override
  void rejectGesture(int pointer) {
    acceptGesture(pointer);  //override rejectGesture here
  }
}

class WebViewExample extends StatefulWidget {
  const WebViewExample({super.key});
  @override
  WebViewExampleState createState() => WebViewExampleState();
}

class WebViewExampleState extends State<WebViewExample> {
  late final WebViewController _controller;
  late final String _adblockerJS;
  late final String _hideOtherAreaJS;
  final ScrollController  _pageSelectorController = ScrollController();
  bool _scrollingDown = false;
  int? _canDeleteIndex;
  bool _addedToFavorite = false;
  int _isLoadingChapter = 0;
  bool _showNoChapterDialog = false;
  bool _isLastChapter = true;
  bool _listPageSelector = false;
  int _totalPages = 1;
  String currentUrl = '';
  String currentComic = '';
  String currentComicChap = '';
  String currentPage = '';

  Future<void> setJsFiles() async{
    _adblockerJS = await rootBundle.loadString('lib/assets/adblocker.js');
    _hideOtherAreaJS = await rootBundle.loadString('lib/assets/hideOtherArea.js');
  }
  
  Future<void> hideAds() async{
    await _controller.runJavaScript(_adblockerJS);
  }

  Future<void> showMangaBoxOnly() async{
    await _controller.runJavaScript(_hideOtherAreaJS);
  }

  RegExp comicPattern = RegExp(r'https://m\.manhuagui\.com/comic/(\d+)/(\d+)\.html');
  Future<void> addComicToFavorite() async{
    String? url = await _controller.currentUrl();
    if(url != null && comicPattern.hasMatch(url)){
      var match = comicPattern.firstMatch(url);
      String? title = await _controller.getTitle();
      String comicName = title!.split('-')[0].split('_')[0];
      String comicId = match!.group(1)!;
      String bCover = "https://cf.mhgui.com/cpic/g/$comicId.jpg";
      String comicChapter = title.split('-')[0].split('_')[1];
      String comicPage = url.contains('=') ? url.split('=')[1] : "1";

      String favoriteItem = '漫畫: $comicName, ID: $comicId, Cover: $bCover, URL: $url, Chapter: $comicChapter, Page: $comicPage';
      saveFavorite(favoriteItem);
    }else{
      print("當前不是漫畫頁面");
    }
  }

  Future<bool> checkComicInFavorite() async{
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList('favorites') ?? [];
    String? url = await _controller.currentUrl();
    if(url != null && comicPattern.hasMatch(url)){
      var match = comicPattern.firstMatch(url);
      String comicId = match!.group(1)!;
      int index = favorites.indexWhere((item) => RegExp(r'ID: (\w*)').firstMatch(item)?.group(1) == comicId);
      return index == -1 ? false : true;
    }else{
      return false;
    }
  }

  Future<void> saveFavorite(String favoriteItem) async{
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList('favorites') ?? [];
    int index = favorites.indexWhere(
      (item) => RegExp(r'ID: (\w*)').firstMatch(item)?.group(1) == RegExp(r'ID: (\w*)').firstMatch(favoriteItem)?.group(1)
    );

    if(index == -1){
      setState(() {
        favorites.add(favoriteItem);
        _addedToFavorite = true;
      });
      print("已加入收藏清單");
      await prefs.setStringList('favorites', favorites);
    } 
    else {
      updateFavorite(index, favoriteItem);
    }
  }

  Future<void> updateFavorite(int index, String favoriteItem) async{
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList('favorites') ?? [];
    setState(() {
      favorites[index] = favoriteItem;
    });
    await prefs.setStringList('favorites', favorites);
  }

  Future<void> removeFavorite(String favoriteItem) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    List<String> favorites = prefs.getStringList('favorites') ?? [];
    setState(() {
      favorites.remove(favoriteItem);
      _addedToFavorite = false;
    });
    await prefs.setStringList('favorites', favorites);
  }

  Future<List<String>> getFavorites() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('favorites') ?? [];
  }

  void loadingScreen(int loadingType,int delay){
    setState(() => _isLoadingChapter = loadingType);
    Future.delayed(Duration(milliseconds: delay), (){
      setState(() => _isLoadingChapter = 0);
      if(loadingType==2) _controller.clearCache();
    });
  }

  @override
  void initState() {
    super.initState();
    setJsFiles();
    _controller = WebViewController()
      ..canGoBack()..canGoForward()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..clearCache()
      ..setOnJavaScriptAlertDialog((request) async{
        print(request.message);
        if(request.message == "没有上一章了" || request.message == "没有下一章了"){
          setState((){
            _isLoadingChapter = 0;
            _showNoChapterDialog = true;
            _isLastChapter = request.message == "没有下一章了" ? true : false;
          });
          Future.delayed(const Duration(seconds: 2),(){setState(() => _showNoChapterDialog = false);});
        }
      })
      ..setNavigationDelegate(NavigationDelegate(
        onUrlChange: (change) async{
          String? url = await _controller.currentUrl();
          if (comicPattern.hasMatch(url!)) {
            
            showMangaBoxOnly();
            Object? page = await _controller.runJavaScriptReturningResult('''
              document.querySelector('.manga-page').textContent;
            '''); 
            setState(() {
              currentPage = page.toString().replaceAll(RegExp(r'["]'), '');
              if(currentPage != '' && currentPage.split('/').length>1) _totalPages = int.tryParse(currentPage.split('/')[1].replaceAll(RegExp(r'P'), '')) ?? 1;
            });
          }
          hideAds();
          
          setState(() {
            currentUrl = url; 
          });
          //print('PageChanged ${change.url}');
        },
        onPageStarted: (url) {
          _isLoadingChapter = 0;
        },
        onPageFinished: (url) async {
          //print('onPageFinished : $url');
          String? title = await _controller.getTitle(); 
          _addedToFavorite = await checkComicInFavorite();
          if(_addedToFavorite) addComicToFavorite();

          if (comicPattern.hasMatch(url)) {
            Object? page = await _controller.runJavaScriptReturningResult('''
              document.querySelector('.manga-page').textContent;
            '''); 
            
            setState(() {
              currentPage = page.toString().replaceAll(RegExp(r'["]'), '');
              if(currentPage != '' && currentPage.split('/').length>1) _totalPages = int.tryParse(currentPage.split('/')[1].replaceAll(RegExp(r'P'), '')) ?? 1;
            });
          } 
          setState((){
            currentComic = title?.split('-')[0].split('_')[0] ?? "Undefine";
            currentComicChap = title?.split('-')[0].split('_')[1] ?? "";
          });
          print(title);
        },
      ))
      ..loadRequest(Uri.parse('https://manhuagui.com')
    );
  }
  

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async{
        if (await _controller.canGoBack()) {
          _controller.goBack(); // 返回上一頁
          return; // 攔截返回鍵事件
        }
        SystemNavigator.pop(); // 如果無法返回上一頁，允許返回鍵退出程式
      },
      child: Scaffold(
        backgroundColor: Colors.black45,
        onDrawerChanged: (isOpened) {
          if(!isOpened) {setState(() => _canDeleteIndex = null);}
          else { setState(() => _scrollingDown = false);}
        },
        drawer: Drawer(
          backgroundColor: Colors.blue[400],
          child: Builder(
            builder: (context) {
              return SafeArea(
                child: Column(
                  children: [
                    const SizedBox(
                      //height: 60,
                      child: Center(
                        child: Text(
                          '我的書櫃', 
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)
                        )
                      )
                    ),
                    Expanded(
                      child: SizedBox(
                        width: double.infinity,
                        child: favoriteListWidget(context),
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: IconButton(
                        onPressed: () async{
                          _controller.loadRequest(Uri.parse('https://m.manhuagui.com'));
                          Scaffold.of(context).closeDrawer();
                        },
                        icon: const Icon(Icons.home, color: Colors.white, size: 35),
                      ),
                    ),
                  ],
                ),
              );
            }
          ),
        ),
        body: Stack(
          children: [
            SafeArea(
              child: WebViewWidget(
                controller: _controller,
                gestureRecognizers: Set()
                ..add(
                  Factory<AllowVerticalDragGestureRecognizer>(() => 
                    AllowVerticalDragGestureRecognizer()
                    ..onUpdate = (DragUpdateDetails details){
                      if(details.delta.dy > 0 && _scrollingDown==false && details.primaryDelta!>15){
                        //print("Scrolling Down : $_scrollingDown");
                        setState(() => _scrollingDown = true);
                      } else if(details.delta.dy < 0 && details.primaryDelta!<-15){
                        setState(() => _scrollingDown = false);
                      }
                    }
                  )
                )
                ..add(
                  Factory<AllowTapGestureRecognizer>(() =>
                    AllowTapGestureRecognizer()
                    ..onTap = () async{
                      if(comicPattern.hasMatch(currentUrl)){
                        int? pPage = int.tryParse(currentPage.split('/')[0]) ?? 1;
                        int? lPage = _totalPages;

                        Future.delayed(const Duration(milliseconds: 50), () async{
                          String? u = await _controller.currentUrl();
                          var p = RegExp(r"#p=(\d+)").firstMatch(u!)?.group(1) ?? 1;
                          int? cPage = int.tryParse(p.toString());
                          //print('Previous Page: $pPage, Current Page: $cPage, Last Page: $lPage');

                          if(cPage==1 && pPage==1){loadingScreen(1, 2000);} //! Previous Chapter
                          else if(pPage==lPage && cPage==pPage){loadingScreen(2, 2000);} //! Next Chapter
                        });
                      }
                      setState((){
                        _scrollingDown = false;
                        _listPageSelector = false;
                      });
                    }
                  )
                )
              ),
            ),
            //! AppBar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 300),
              top: _scrollingDown ? 0 : -100, // 隱藏時移動到螢幕外
              left: 0,
              right: 0,
              child: Container(
                width: 1000,
                decoration: const BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(15), bottomRight: Radius.circular(15))
                ),
                padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                child: SafeArea(
                  child: Builder(
                    builder: (context){
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.collections_bookmark_rounded, color: Colors.white, size: 30),
                            onPressed: () {
                              Scaffold.of(context).openDrawer();
                            },
                          ),
                          Flexible(
                            child: InkWell(
                              onTap: (){
                                String? url = currentUrl.replaceFirst(RegExp(r'(?<=comic/\d+)/.*'), '');
                                _controller.loadRequest(Uri.parse(url));
                                //print(url);
                              },
                              child: FittedBox(
                                fit: BoxFit.fitHeight,
                                child: Text(
                                  "$currentComic $currentComicChap",
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    overflow: TextOverflow.clip
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _addedToFavorite ? Icons.bookmark_added : Icons.bookmark_add_outlined, 
                              color: Colors.white, size: 30
                            ),
                            onPressed: () async{
                              if(_addedToFavorite){
                                String? url = currentUrl;
                                SharedPreferences prefs = await SharedPreferences.getInstance();
                                List<String> favorites = prefs.getStringList('favorites') ?? [];
                                var match = comicPattern.firstMatch(url);
                                String comicId = match!.group(1)!;
                                var i = favorites.where((item) => RegExp(r'ID: (\w*)').firstMatch(item)?.group(1) == comicId);
                                removeFavorite(i.toString().replaceAll(RegExp(r'[()]'), ''));
                              }else{
                                await addComicToFavorite();
                              }
                            },
                          )
                        ],
                      );
                    }
                  ),
                ),
              ),
            ),
            //! Alert Dialog
            AnimatedPositioned(
              top: _showNoChapterDialog ? 30 : -100,
              width: MediaQuery.of(context).size.width,
              duration: const Duration(milliseconds: 300),
              child: SafeArea(
                child: Container(
                  alignment: Alignment.center,
                  margin: EdgeInsets.symmetric(horizontal: _isLastChapter ? 110 : 120),
                  height: 30,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(15),
                    color: Colors.blue[400]
                  ),
                  child: Text(
                    _isLastChapter ? "已經是最後一章了" : "這才第一章而已", 
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white
                    ),
                  ),
                ),
              ), 
            
            ),
            //! PagePicker
            Positioned(
            bottom: 25, right: 0,
              child: AnimatedContainer(
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), topRight: Radius.circular(10))
                ),
                height: _listPageSelector ? 150 : 0, width: 60,
                duration: const Duration(milliseconds: 400),
                margin: const EdgeInsets.all(10),
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 10),
                  controller: _pageSelectorController,
                  itemCount: _totalPages,
                  itemBuilder: (context, index) {
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() => _listPageSelector = false);
                          String url;
                          if (currentUrl.contains('#p=')) {url = currentUrl.replaceAll(RegExp(r"#p=(\d+)"), "#p=${index + 1}");}
                          else {url = "$currentUrl#p=${index + 1}";}
                          _controller.loadRequest(Uri.parse(url));
                          if(_pageSelectorController.hasClients){
                            _pageSelectorController.jumpTo(0);
                          }
                        },
                        splashColor: Colors.blue[200],
                        child: Container(
                          height: 30, 
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          child: FittedBox(
                            fit: BoxFit.contain,
                            child: Text(
                              "第 ${index+1} 頁", 
                              style: const TextStyle(color: Colors.black),
                              textAlign: TextAlign.center,
                            ),
                          )
                        ),
                      ),
                    );
                  },
                ),
              )
            ),
            //! ChapterButton
            AnimatedPositioned(
              bottom: 10, right: _listPageSelector ? 80 : 8,
              duration: const Duration(milliseconds: 300),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 300),
                opacity: _listPageSelector ? 1 : 0,
                child: Row(
                  children: [
                    SizedBox(
                      height: 30, width: 30,
                      child: IconButton(

                        padding: EdgeInsets.zero,
                        onPressed: (){
                          _listPageSelector = false;
                          _controller.runJavaScript('''
                          var button = document.querySelector('a[data-action="chapter.prev"]');
                          if (button) {button.click();}
                        ''');
                          loadingScreen(1, 2000);
                        }, 
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey[300]
                        ),
                        icon: const Icon(Icons.keyboard_double_arrow_left_rounded)
                      ),
                    ),
                    const SizedBox(width: 5),
                    SizedBox(
                      height: 30, width: 30,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: (){
                          _listPageSelector = false;
                          _controller.runJavaScript('''
                            var button = document.querySelector('a[data-action="chapter.next"]');
                            if (button) {button.click();}
                          ''');
                          loadingScreen(2, 2000);
                        }, 
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.grey[300]
                        ),
                        icon: const Icon(Icons.keyboard_double_arrow_right_rounded)
                      ),
                    ),
                  ],
                ),
              )
            ),
            //! PageButton
            Positioned(
              bottom: 0, right: 0,
              child: comicPattern.hasMatch(currentUrl)
              ? InkWell(
                child: Container(
                  margin: const EdgeInsets.all(10),
                  height: 30, width: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(10)
                  ),
                  child: FittedBox(
                    fit: BoxFit.contain, 
                    child: Text(currentPage)
                  ),
                ),
                onTap: () {
                  setState(() => _listPageSelector = !_listPageSelector);
                },
              )
              : const SizedBox.shrink()
            ),
            //! Loading Screen
            Positioned.fill(
              child: _isLoadingChapter == 0
              ? const SizedBox.shrink()
              : Container(
                alignment: Alignment.center,
                color: Colors.black.withOpacity(0.4),
                child: Text(
                  _isLoadingChapter==1 ? "正在載入上一章" : "正在載入下一章",
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white
                  ),
                ),
              )
            )
          ],
        ),
      ),
    );
  }

  Widget favoriteListWidget(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: getFavorites(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const CircularProgressIndicator();
        } else 
        if (snapshot.hasError) {
          return const Text("載入錯誤", style: TextStyle(color: Colors.white));
        } else if (snapshot.data!.isEmpty) {
          return const Center(child: Text("沒有收藏的漫畫😢", style: TextStyle(color: Colors.white)));
        } else {
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            itemCount: snapshot.data!.length,
            itemBuilder: (context, index) {
              String favorite = snapshot.data![index];
              String favoriteName = RegExp(r'漫畫: ([^,]+)').firstMatch(favorite)?.group(1) ?? "Undefine";
              String favoriteChapter = RegExp(r'Chapter: ([^,]+)').firstMatch(favorite)?.group(1) ?? "Undefine";
              String favoritePage = RegExp(r'Page: ([^,]+)').firstMatch(favorite)?.group(1) ?? "Undefine";
              String favoriteCover = RegExp(r'Cover: (https?://[^\s]+)').firstMatch(favorite)?.group(1) ?? "Unknow";
              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    splashColor: Colors.blue[400],
                    onTap: () async {
                      String url = RegExp(r'URL: (https?://[^,]+)').firstMatch(favorite)!.group(1)!;
                      _controller.loadRequest(Uri.parse(url));
                      Scaffold.of(context).closeDrawer();
                      setState(() => _scrollingDown = false);
                    },
                    onLongPress: () {
                      setState(() {
                        _canDeleteIndex = _canDeleteIndex == index ? null : index;
                      });
                    },
                    child: ListTile(
                      contentPadding: const EdgeInsets.only(left: 10, top: 5, bottom: 5, right: 0),
                      visualDensity: const VisualDensity(horizontal: 0, vertical: 2),

                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color:Colors.white, width: 1.5)
                      ),

                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            favoriteName, 
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, height: 1, color: Colors.white)
                          ),
                          Wrap(
                            children: [
                              const Text(
                                '上次看到 ',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70),
                              ),
                              Text(
                                '$favoriteChapter第$favoritePage頁',
                                style: const TextStyle(fontSize: 11, color: Colors.white54),
                              )
                            ],
                          ),
                        ],
                      ),

                      leading: favoriteCover != 'Unknow'
                        ? Image.network(favoriteCover, fit: BoxFit.cover)
                        : const Icon(Icons.error_outline),
                      
                      trailing: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _canDeleteIndex == index
                        ? IconButton(
                            key: ValueKey<int>(index),
                            icon: Icon(Icons.delete_forever, color: Colors.red[400], size: 35),
                            onPressed: () {
                              removeFavorite(favorite);
                              setState(() => _addedToFavorite = false);
                            },
                          )
                        : const SizedBox.shrink()
                      ),
                        
                    ),
                  ),
                ),
              );
            },
          );
        }
      },
    );
  }

}

