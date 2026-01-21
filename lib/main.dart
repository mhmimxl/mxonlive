import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart' as fcm; 
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:marquee/marquee.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

// --- CONFIGURATION ---
const String primaryConfigUrl = "https://raw.githubusercontent.com/mxonlive/mxonlive.github.io/refs/heads/main/live/mxonlive_app_1.json";
const String backupConfigUrl = "https://mxonlive.short.gy/mxonlive_app_json"; 

const String telegramUrl = "https://t.me/mxonlive";
const String contactEmail = "mailto:sultanarabi161@gmail.com";
const String appName = "mxonlive";

const Map<String, String> secureHeaders = {
  "User-Agent": "mxonlive-agent/2.0.0 (Android; Secure)",
};

// --- SMART CACHE MANAGER (Limit: ~200MB) ---
final customCacheManager = fcm.CacheManager(
  fcm.Config(
    'mxonlive_cache_v3', 
    stalePeriod: const Duration(days: 7), 
    maxNrOfCacheObjects: 1000, 
    repo: fcm.JsonCacheInfoRepository(databaseName: 'mxonlive_cache_v3'),
    fileService: fcm.HttpFileService(),
  ),
);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MxOnLiveApp());
}

// --- MODELS ---
class ServerItem {
  final String id;
  final String name;
  final String url;
  ServerItem({required this.id, required this.name, required this.url});
}

class Channel {
  final String name;
  final String logo;
  final String url;
  final String group;
  Channel({required this.name, required this.logo, required this.url, required this.group});
}

class AppConfig {
  String notice;
  String aboutNotice;
  Map<String, dynamic>? updateData;
  List<ServerItem> servers;

  AppConfig({
    this.notice = "Welcome to mxonlive",
    this.aboutNotice = "No details available.",
    this.updateData,
    this.servers = const [],
  });
}

// --- APP ROOT ---
class MxOnLiveApp extends StatelessWidget {
  const MxOnLiveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0F0F),
        primaryColor: const Color(0xFFFF3B30),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF141414),
          elevation: 0,
          centerTitle: true,
          titleTextStyle: TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
        ),
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
        cardTheme: CardThemeData(
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const SplashScreen(),
    );
  }
}

// --- REUSABLE LOGO WIDGET ---
class ChannelLogo extends StatelessWidget {
  final String url;
  const ChannelLogo({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12.0),
        child: Image.asset('assets/logo.png', color: Colors.white.withOpacity(0.5)),
      );
    }
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: customCacheManager,
      fit: BoxFit.contain,
      placeholder: (context, url) => const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.redAccent))),
      errorWidget: (context, url, error) => Padding(
        padding: const EdgeInsets.all(12.0),
        child: Image.asset('assets/logo.png', color: Colors.white.withOpacity(0.5)),
      ),
    );
  }
}

// --- SPLASH SCREEN ---
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 40)],
                borderRadius: BorderRadius.circular(20),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.asset('assets/logo.png', width: 120, height: 120, errorBuilder: (c,o,s)=>const Icon(Icons.play_circle_filled, size: 100, color: Colors.red)),
              ),
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: Colors.redAccent),
            const SizedBox(height: 10),
            const Text("Welcome", style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// --- HOME PAGE ---
class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  AppConfig appConfig = AppConfig();
  ServerItem? selectedServer;
  List<Channel> allChannels = [];
  Map<String, List<Channel>> groupedChannels = {};
  bool isConfigLoading = true;
  bool isPlaylistLoading = false;
  TextEditingController searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    fetchConfig();
  }

  void _showError(String message) {
    if(!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [const Icon(Icons.wifi_off, color: Colors.white), const SizedBox(width: 10), Expanded(child: Text(message))]),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      )
    );
  }

  Future<void> fetchConfig() async {
    setState(() { isConfigLoading = true; });
    try {
      await _fetchFromUrl(primaryConfigUrl);
    } catch (e) {
      print("Primary Failed. Backup...");
      try {
        await _fetchFromUrl(backupConfigUrl);
      } catch (e2) {
        setState(() { isConfigLoading = false; });
        _showError("Connection Failed. All Servers Down.");
      }
    }
  }

  Future<void> _fetchFromUrl(String url) async {
    final res = await http.get(Uri.parse(url), headers: secureHeaders).timeout(const Duration(seconds: 10));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      _parseConfig(data);
    } else {
      throw Exception("Status ${res.statusCode}");
    }
  }

  void _parseConfig(Map<String, dynamic> data) {
    List<ServerItem> loadedServers = [];
    if (data['servers'] != null) {
      for (var s in data['servers']) {
        loadedServers.add(ServerItem(id: s['id'], name: s['name'], url: s['url']));
      }
    }

    setState(() {
      appConfig = AppConfig(
        notice: data['notice'] ?? "Welcome",
        aboutNotice: data['about_notice'] ?? "No info provided.",
        updateData: data['update_data'],
        servers: loadedServers,
      );
      
      if (loadedServers.isNotEmpty) {
        selectedServer = loadedServers[0];
        isConfigLoading = false;
        loadPlaylist(loadedServers[0].url);
      } else {
        isConfigLoading = false;
        _showError("Maintenance Mode.");
      }
    });
  }

  Future<void> loadPlaylist(String url) async {
    setState(() { isPlaylistLoading = true; searchController.clear(); });
    try {
      final response = await http.get(Uri.parse(url), headers: secureHeaders).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        parseM3u(response.body);
      } else {
        throw Exception("Failed");
      }
    } catch (e) {
      setState(() { isPlaylistLoading = false; });
      _showError("Playlist Error. Check Connection.");
    }
  }

  void parseM3u(String content) {
    List<String> lines = const LineSplitter().convert(content);
    List<Channel> channels = [];
    String? name;
    String? logo;
    String? group;

    for (String line in lines) {
      if (line.startsWith("#EXTINF:")) {
        final nameMatch = RegExp(r',(.*)').firstMatch(line);
        name = nameMatch?.group(1)?.trim() ?? "Unknown";
        final logoMatch = RegExp(r'tvg-logo="([^"]*)"').firstMatch(line);
        logo = logoMatch?.group(1) ?? "";
        final groupMatch = RegExp(r'group-title="([^"]*)"').firstMatch(line);
        group = groupMatch?.group(1) ?? "Others";
      } else if (line.isNotEmpty && !line.startsWith("#")) {
        if (name != null) {
          channels.add(Channel(name: name, logo: logo ?? "", url: line.trim(), group: group ?? "Others"));
          name = null;
        }
      }
    }

    setState(() {
      allChannels = channels;
      _updateGroupedChannels(channels);
      isPlaylistLoading = false;
    });
  }

  void _onSearchChanged(String query) {
    if (query.isEmpty) {
      setState(() { _updateGroupedChannels(allChannels); });
    } else {
      final filtered = allChannels.where((c) => c.name.toLowerCase().contains(query.toLowerCase())).toList();
      setState(() { _updateGroupedChannels(filtered); });
    }
  }

  void _updateGroupedChannels(List<Channel> channels) {
    Map<String, List<Channel>> groups = {};
    for (var ch in channels) {
      if (!groups.containsKey(ch.group)) {
        groups[ch.group] = [];
      }
      groups[ch.group]!.add(ch);
    }
    var sortedKeys = groups.keys.toList()..sort();
    groupedChannels = { for (var k in sortedKeys) k: groups[k]! };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(appName, style: TextStyle(letterSpacing: 1.5)),
        centerTitle: true,
        leading: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Image.asset('assets/logo.png', errorBuilder: (c,o,s)=>const Icon(Icons.tv, color: Colors.red)),
        ),
        leadingWidth: 50,
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white70),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InfoPage(config: appConfig))),
          ),
          const SizedBox(width: 8)
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async { await fetchConfig(); },
        color: Colors.redAccent,
        backgroundColor: const Color(0xFF1E1E1E),
        child: isConfigLoading 
            ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
            : Column(
                children: [
                  // Notice
                  Container(
                    height: 38,
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF252525),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            color: Colors.redAccent.withOpacity(0.1),
                            height: double.infinity,
                            child: const Icon(Icons.notifications_active, size: 16, color: Colors.redAccent),
                          ),
                          Expanded(
                            child: Marquee(
                              text: appConfig.notice,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
                              scrollAxis: Axis.horizontal,
                              blankSpace: 20.0,
                              velocity: 40.0,
                              startPadding: 10.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Search
                  Container(
                    height: 45,
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E1E),
                      borderRadius: BorderRadius.circular(50),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: TextField(
                      controller: searchController,
                      onChanged: _onSearchChanged,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Search channels...",
                        hintStyle: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                        prefixIcon: const Icon(Icons.search, color: Colors.grey),
                        suffixIcon: searchController.text.isNotEmpty 
                          ? IconButton(icon: const Icon(Icons.clear, size: 18, color: Colors.grey), onPressed: () { searchController.clear(); _onSearchChanged(""); }) 
                          : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Servers
                  SizedBox(
                    height: 40,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: appConfig.servers.length,
                      itemBuilder: (ctx, index) {
                        final srv = appConfig.servers[index];
                        final isSelected = selectedServer?.id == srv.id;
                        return Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: ChoiceChip(
                            label: Text(srv.name, style: const TextStyle(fontSize: 12)),
                            selected: isSelected,
                            onSelected: (_) {
                              setState(() => selectedServer = srv);
                              loadPlaylist(srv.url);
                            },
                            selectedColor: Colors.blueAccent,
                            backgroundColor: const Color(0xFF1E1E1E),
                            labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.grey),
                            side: BorderSide.none,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(50)),
                            showCheckmark: false,
                          ),
                        );
                      },
                    ),
                  ),
                  const Divider(color: Colors.white10, height: 20),

                  // Content
                  Expanded(
                    child: isPlaylistLoading
                        ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent))
                        : _buildGroupedChannelList(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildGroupedChannelList() {
    if (groupedChannels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off, size: 40, color: Colors.grey),
            const SizedBox(height: 10),
            Text("No channels found.", style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: () => selectedServer != null ? loadPlaylist(selectedServer!.url) : fetchConfig(), 
              icon: const Icon(Icons.refresh), label: const Text("Refresh")
            )
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: groupedChannels.length,
      itemBuilder: (context, index) {
        String groupName = groupedChannels.keys.elementAt(index);
        List<Channel> channels = groupedChannels[groupName]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 15, 20, 8),
              child: Row(
                children: [
                  Container(width: 4, height: 16, color: Colors.redAccent, margin: const EdgeInsets.only(right: 8)),
                  Text(groupName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  const Spacer(),
                  Text("${channels.length}", style: TextStyle(color: Colors.grey.shade700, fontSize: 11)),
                ],
              ),
            ),
            GridView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                childAspectRatio: 0.8,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: channels.length,
              itemBuilder: (ctx, i) {
                final channel = channels[i];
                return GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PlayerScreen(channel: channel, allChannels: allChannels)),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E1E),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: ChannelLogo(url: channel.logo),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

// --- PLAYER SCREEN ---
class PlayerScreen extends StatefulWidget {
  final Channel channel;
  final List<Channel> allChannels;
  const PlayerScreen({super.key, required this.channel, required this.allChannels});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  late List<Channel> relatedChannels;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    relatedChannels = widget.allChannels
        .where((c) => c.group == widget.channel.group && c.name != widget.channel.name)
        .toList();
    initializePlayer();
  }

  Future<void> initializePlayer() async {
    try {
      _videoPlayerController = VideoPlayerController.networkUrl(
        Uri.parse(widget.channel.url),
        httpHeaders: secureHeaders,
      );
      await _videoPlayerController.initialize();
      
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController,
        autoPlay: true,
        looping: false,
        isLive: true,
        aspectRatio: 16 / 9,
        allowedScreenSleep: false,
        showControls: true,
        materialProgressColors: ChewieProgressColors(
          playedColor: Colors.redAccent,
          handleColor: Colors.redAccent,
          backgroundColor: Colors.grey.shade800,
          bufferedColor: Colors.white30,
        ),
        errorBuilder: (context, errorMessage) => const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 40),
              SizedBox(height: 10),
              Text("Stream Offline / Error", style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      );
      setState(() {});
    } catch (e) {
       // Log
    }
  }

  @override
  void dispose() {
    _videoPlayerController.dispose();
    _chewieController?.dispose();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.channel.name)),
      body: SafeArea(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Container(
                color: Colors.black,
                child: _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                    ? Chewie(controller: _chewieController!)
                    : const Center(child: CircularProgressIndicator(color: Colors.redAccent)),
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () => launchUrl(Uri.parse(telegramUrl), mode: LaunchMode.externalApplication),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      color: const Color(0xFF0088CC),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.telegram, color: Colors.white),
                          SizedBox(width: 10),
                          Text("JOIN TELEGRAM CHANNEL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Align(alignment: Alignment.centerLeft, child: Text("More from this Category", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey))),
                  ),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      itemCount: relatedChannels.length,
                      itemBuilder: (ctx, index) {
                        final ch = relatedChannels[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          leading: Container(
                            width: 60, height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: ChannelLogo(url: ch.logo),
                          ),
                          title: Text(ch.name, style: const TextStyle(color: Colors.white)),
                          subtitle: Text(ch.group, style: const TextStyle(color: Colors.grey, fontSize: 10)),
                          trailing: const Icon(Icons.play_circle_outline, color: Colors.redAccent),
                          onTap: () => Navigator.pushReplacement(
                            context, MaterialPageRoute(builder: (_) => PlayerScreen(channel: ch, allChannels: widget.allChannels))
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- INFO PAGE ---
class InfoPage extends StatelessWidget {
  final AppConfig config;
  const InfoPage({super.key, required this.config});

  @override
  Widget build(BuildContext context) {
    final update = config.updateData;
    final hasUpdate = update != null && update['show'] == true;

    return Scaffold(
      appBar: AppBar(title: const Text("About & Updates")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            if (hasUpdate)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 20),
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF007AFF), Color(0xFF00C6FF)]),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.4), blurRadius: 10)],
                ),
                child: Column(
                  children: [
                    const Icon(Icons.system_update, color: Colors.white, size: 40),
                    const SizedBox(height: 10),
                    Text(
                      update!['version'] ?? "New Update",
                      style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      update['note'] ?? "New features available!",
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 15),
                    ElevatedButton(
                      onPressed: () {
                        if (update['download_url'] != null) {
                          launchUrl(Uri.parse(update['download_url']), mode: LaunchMode.externalApplication);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.blueAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      child: const Text("Download Update"),
                    )
                  ],
                ),
              ),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [Icon(Icons.info, color: Colors.orangeAccent), SizedBox(width: 10), Text("Notice", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18))]),
                  const Divider(color: Colors.white10),
                  Text(
                    config.aboutNotice,
                    style: const TextStyle(color: Colors.white70, height: 1.5),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 20),

            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(backgroundColor: Colors.redAccent, child: Icon(Icons.person, color: Colors.white)),
              title: const Text("Developed by Sultan Arabi"),
              subtitle: const Text("- Developer"),
              trailing: IconButton(
                icon: const Icon(Icons.email, color: Colors.white),
                onPressed: () => launchUrl(Uri.parse(contactEmail)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
