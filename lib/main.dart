import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:rtc_link/pages/chat_page.dart';
import 'package:rtc_link/splash-screen.dart';
import 'package:url_launcher/url_launcher.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WebRTC Firebase Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Color(0XFF00A884)),
        useMaterial3: false,
        fontFamily: "Regular",
      ),
      home: Splashscreen(),
    );
  }
}

class VideoCallScreen extends StatefulWidget {
  const VideoCallScreen({super.key});

  @override
  State<VideoCallScreen> createState() => _VideoCallScreenState();
}

class _VideoCallScreenState extends State<VideoCallScreen> {
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  final _roomIdController = TextEditingController();

  MediaStream? _localStream;
  RTCPeerConnection? _peerConnection;

  CollectionReference? _callerCandidates;
  CollectionReference? _calleeCandidates;
  DocumentReference? _roomDoc;

  final _firestore = FirebaseFirestore.instance;
  bool _cameraEnabled = true;

  @override
  void initState() {
    super.initState();
    _initRenderers();
    _getUserMedia();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _roomIdController.dispose();
    _peerConnection?.dispose();
    _localStream?.dispose();
    super.dispose();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  Future<void> _getUserMedia() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {'facingMode': 'user'},
    });
    _localRenderer.srcObject = stream;
    setState(() {
      _localStream = stream;
    });
  }

  Future<void> _toggleCamera() async {
    if (_localStream == null) return;

    final videoTrack = _localStream!
        .getVideoTracks()
        .firstWhere((track) => track.kind == 'video');

    setState(() {
      _cameraEnabled = !_cameraEnabled;
      videoTrack.enabled = _cameraEnabled;
    });
  }

  Future<void> _createPeerConnection() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

    final pc = await createPeerConnection(config);

    _localStream?.getTracks().forEach((track) {
      pc.addTrack(track, _localStream!);
    });

    pc.onIceCandidate = (candidate) async {
      if (candidate == null) return;
      final candidateData = {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      };
      if (_callerCandidates != null) {
        await _callerCandidates!.add(candidateData);
      } else if (_calleeCandidates != null) {
        await _calleeCandidates!.add(candidateData);
      }
    };

    pc.onTrack = (event) {
      if (event.track.kind == 'video' && event.streams.isNotEmpty) {
        _remoteRenderer.srcObject = event.streams[0];
      }
    };

    _peerConnection = pc;
  }

  Future<void> _createRoom() async {
    final room = _firestore.collection('rooms').doc();
    _roomDoc = room;
    _roomIdController.text = room.id;

    await _createPeerConnection();
    _callerCandidates = room.collection('callerCandidates');

    final offer = await _peerConnection!.createOffer();
    await _peerConnection!.setLocalDescription(offer);

    await room.set({
      'offer': {'type': offer.type, 'sdp': offer.sdp},
    });

    room.snapshots().listen((snapshot) async {
      final data = snapshot.data();
      if (data != null && data['answer'] != null) {
        final answer = data['answer'];
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(answer['sdp'], answer['type']),
        );
      }
    });

    room.collection('calleeCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          _peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      }
    });
  }

  Future<void> _joinRoom(String roomId) async {
    final room = _firestore.collection('rooms').doc(roomId);
    _roomDoc = room;

    final data = (await room.get()).data();
    if (data == null) return;

    await _createPeerConnection();
    _calleeCandidates = room.collection('calleeCandidates');

    final offer = data['offer'];
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offer['sdp'], offer['type']),
    );

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    await room.update({
      'answer': {'type': answer.type, 'sdp': answer.sdp},
    });

    room.collection('callerCandidates').snapshots().listen((snapshot) {
      for (var change in snapshot.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data()!;
          _peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
        }
      }
    });
  }

  Future<void> _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _endCall() {
    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _localStream?.getTracks().forEach((track) => track.stop());
    _peerConnection?.close();
    setState(() {
      _localStream = null;
      _peerConnection = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text("RTCLink", style: TextStyle(color: Colors.white)),
          elevation: 1,
          centerTitle: true,
          backgroundColor: Color(0xff008069),
          bottom: const TabBar(
            tabs: [
              Icon(Icons.video_camera_front, size: 30),
              Text(
                "Home",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Icon(Icons.audio_file, size: 30),
            ],
            indicatorColor: Colors.white,
          ),
          toolbarHeight: 80,
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            children: [
              TextField(
                controller: _roomIdController,
                decoration: InputDecoration(
                  labelText: 'Room ID',
                  hintText: "Enter Id...",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Color(0xff008069)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton(
                    onPressed: _createRoom,
                    child: const Text('Create Room', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: Color(0xff008069)),
                  ),
                  ElevatedButton(
                    onPressed: () => _joinRoom(_roomIdController.text),
                    child: const Text('Join Room', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(backgroundColor: Color(0xff008069)),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildLabel("Local Video"),
              SizedBox(height: 11),
              SizedBox(height: 250, child: RTCVideoView(_localRenderer, mirror: true)),
              const SizedBox(height: 12),
              _buildLabel("Remote Video"),
              SizedBox(height: 200, child: RTCVideoView(_remoteRenderer)),
              const SizedBox(height: 11),
              Text("© 2025 RTCLink — Built for realTime Communication.",
                  style: TextStyle(color: Colors.green.shade900, fontSize: 10)),
              const SizedBox(height: 11),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: FaIcon(FontAwesomeIcons.instagram, color: Colors.pink, size: 34),
                    onPressed: () => _launchURL("https://www.instagram.com/vaibhavjoshi_.07/"),
                  ),
                  IconButton(
                    icon: FaIcon(FontAwesomeIcons.linkedin, color: Colors.blueAccent, size: 34),
                    onPressed: () => _launchURL("https://www.linkedin.com/in/vaibhav-joshi-7113b11b5/"),
                  ),
                  IconButton(
                    icon: FaIcon(FontAwesomeIcons.google, color: Colors.orange, size: 34),
                    onPressed: () => _launchURL("mailto:vaibhavjoshi0709@gmail.com"),
                  ),
                  IconButton(
                    icon: FaIcon(FontAwesomeIcons.github, color: Colors.black54, size: 34),
                    onPressed: () => _launchURL("https://github.com/vaibhavjoshi07"),
                  ),
                ],
              ),
            ],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          selectedItemColor: Colors.green.shade700,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.videocam), label: "Toggle Camera"),
            BottomNavigationBarItem(icon: Icon(Icons.call_end), label: "End Call"),
          ],
          onTap: (index) {
            if (index == 0) {
              _toggleCamera();
            } else if (index == 1) {
              _endCall();
            }
          },
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Color(0xff008665),
        child: FaIcon(FontAwesomeIcons.bots,color: Colors.white,),

        onPressed: (){
          Navigator.push(context, MaterialPageRoute(builder: (context){
             return ChatPage();
          }));
        }),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Container(
      width: 200,
      height: 30,
      decoration: BoxDecoration(
        boxShadow: [BoxShadow(color: Colors.black, blurRadius: 4, offset: Offset(0, 2))],
        color: Colors.green.shade400,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.white)),
      ),
    );
  }
}
