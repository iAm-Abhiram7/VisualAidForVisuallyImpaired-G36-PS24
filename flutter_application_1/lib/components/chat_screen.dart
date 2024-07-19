import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_application_1/components/conversation_model.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:ffmpeg_kit_flutter/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ChatScreen extends StatefulWidget {
  final File mediaFile;
  final String? conversationId;
  final bool isVideo;
  
  const ChatScreen({super.key, required this.mediaFile, this.conversationId, required this.isVideo});

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  TextEditingController _textController = TextEditingController();
  List<Map<String, String>> _messages = [];
  late FlutterTts flutterTts;
  late stt.SpeechToText _speechToText;
  ScrollController _scrollController = ScrollController();
  stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String? _conversationId;
  File? _currentImage;
  bool _imageSent = false;
  int _tapCount = 0;
  Timer? _tapTimer;
  String? _videoCaption;
  File? _representativeFrame;
  bool _captionGenerated = false;

  @override
  void initState() {
    super.initState();
    flutterTts = FlutterTts();
    _speechToText = stt.SpeechToText();
    _conversationId = widget.conversationId;
    _currentImage = widget.mediaFile;
    if (_conversationId != null) {
      _loadExistingConversation();
    } else {
      _sendMedia();
    }
  }

  @override
  void dispose() {
    _stopListening();
    _tapTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadExistingConversation() async {
    if (_conversationId == null) return;

    final conversationDoc = await FirebaseFirestore.instance
        .collection('conversations')
        .doc(_conversationId)
        .get();

    if (!conversationDoc.exists) return;

    final conversationData = conversationDoc.data() as Map<String, dynamic>;
    final conversation = Conversation.fromMap(conversationData);

    setState(() {
      _messages = conversation.messages
          .map((message) => {
                'type': message.sender == 'user' ? 'user' : 'response',
                'message': message.text,
              })
          .toList();
      _messages.insert(0, {
        'type': widget.isVideo ? 'video' : 'image',
        'message': conversation.imageUrl,
      });
      _imageSent = true;
      _videoCaption = conversation.imageDescription;
    });

    if (widget.isVideo) {
      _representativeFrame = await extractRepresentativeFrame(_currentImage!);
    }

    _scrollToBottom();
  }

  Future<void> _sendMedia() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() {
      _messages.add({
        'type': widget.isVideo ? 'video' : 'image',
        'message': _currentImage!.path,
      });
      _imageSent = true;
    });

    _scrollToBottom();

    if (widget.isVideo) {
      _videoCaption = await _getVideoCaption(_currentImage!);
      setState(() {
        _messages.add({
          'type': 'response',
          'message': "Video caption: $_videoCaption",
        });
        _captionGenerated = true;
      });
    }

    final conversation = Conversation(
      userId: user.uid,
      imageUrl: _currentImage!.path,
      imageDescription: _videoCaption ?? '',
      messages: [],
      timestamp: DateTime.now(),
      isVideo: widget.isVideo,
    );

    final conversationRef = await FirebaseFirestore.instance
        .collection('conversations')
        .add(conversation.toMap());
    _conversationId = conversationRef.id;
  }

  Future<void> _sendMessage(String message) async {
    if (message.isEmpty) return;

    setState(() {
      _messages.add({
        'type': 'user',
        'message': message,
      });
    });

    _textController.clear();
    _scrollToBottom();

    String response;
    if (widget.isVideo) {
      if (_representativeFrame == null) {
        _representativeFrame = await extractRepresentativeFrame(_currentImage!);
      }
      if (_representativeFrame != null) {
        response = await _getVQAResponse("$_videoCaption. $message", _representativeFrame!);
      } else {
        response = "Sorry, I couldn't process the video frame. Please try again.";
      }
    } else {
      response = await _getVQAResponse(message, _currentImage!);
    }

    setState(() {
      _messages.add({
        'type': 'response',
        'message': response,
      });
    });

    if (_conversationId != null) {
      await FirebaseFirestore.instance
          .collection('conversations')
          .doc(_conversationId)
          .update({
        'messages': FieldValue.arrayUnion([
          {
            'sender': 'user',
            'text': message,
          },
          {
            'sender': 'model',
            'text': response,
          },
        ]),
      });
    }

    _scrollToBottom();
    await flutterTts.speak(response);
  }

  Future<String> _getVQAResponse(String question, File image) async {
    var request = http.MultipartRequest('POST', Uri.parse('https://8206-35-231-149-136.ngrok-free.app/vqa'));
    request.fields['question'] = question;
    request.files.add(await http.MultipartFile.fromPath('image', image.path));

    var response = await request.send();
    if (response.statusCode == 200) {
      var responseData = await response.stream.bytesToString();
      var decodedResponse = json.decode(responseData);
      return decodedResponse['answer'];
    } else {
      return 'Error: ${response.statusCode}';
    }
  }

  Future<String> _getVideoCaption(File video) async {
    var captionRequest = http.MultipartRequest('POST', Uri.parse('https://8206-35-231-149-136.ngrok-free.app/caption'));
    captionRequest.files.add(await http.MultipartFile.fromPath('video', video.path));

    var captionResponse = await captionRequest.send();
    if (captionResponse.statusCode == 200) {
      var captionData = await captionResponse.stream.bytesToString();
      var decodedCaption = json.decode(captionData);
      return decodedCaption['caption'];
    } else {
      return 'Error generating caption: ${captionResponse.statusCode}';
    }
  }

  Future<File?> extractRepresentativeFrame(File video) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final framePath = '${tempDir.path}/representative_frame.jpg';
      
      final result = await FFmpegKit.execute('-i ${video.path} -vf select=\'eq(n,0)\' -vframes 1 $framePath');
      
      if (await result.getReturnCode() == 0) {
        return File(framePath);
      } else {
        print('FFmpeg process exited with error: ${await result.getOutput()}');
        return null;
      }
    } catch (e) {
      print('Error extracting frame: $e');
      return null;
    }
  }
  
  Future<void> _stopListening() async {
    await _speechToText.stop();
    setState(() {
      _isListening = false;
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Widget _buildMessageBubble(Map<String, String> message) {
    switch (message['type']) {
      case 'user':
        return Align(
          alignment: Alignment.centerRight,
          child: Container(
            padding: EdgeInsets.all(16),
            margin: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              message['message']!,
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
          ),
        );
      case 'response':
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: EdgeInsets.all(16),
            margin: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(message['message']!, style: TextStyle(fontSize: 18)),
          ),
        );
      case 'image':
        return Align(
          alignment: Alignment.center,
          child: Container(
            padding: EdgeInsets.all(16),
            margin: EdgeInsets.all(10),
            child: Image.file(
              File(message['message']!),
              semanticLabel: 'Selected image',
              height: 300,
              width: 300,
            ),
          ),
        );
      case 'video':
        return Align(
          alignment: Alignment.center,
          child: Container(
            padding: EdgeInsets.all(16),
            margin: EdgeInsets.all(10),
            child: Icon(Icons.video_file, size: 100),
          ),
        );
      default:
        return Container();
    }
  }

  void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (status) => print('onStatus: $status'),
        onError: (errorNotification) => print('onError: $errorNotification'),
      );
      if (available) {
        setState(() => _isListening = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Listening...')),
        );
        _speech.listen(
          onResult: (result) {
            if (result.finalResult) {
              _sendMessage(result.recognizedWords);
              setState(() => _isListening = false);
              _speech.stop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Stopped listening')),
              );
            }
          },
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Stopped listening')),
      );
    }
  }

  void _handleTap() {
    _tapCount++;
    if (_tapCount == 1) {
      _tapTimer = Timer(Duration(milliseconds: 500), () {
        _tapCount = 0;
      });
    } else if (_tapCount == 3) {
      _tapCount = 0;
      _tapTimer?.cancel();
      if (_imageSent) {
        _listen();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isVideo ? 'Video Chat' : 'Image Chat', style: TextStyle(fontSize: 28)),
        backgroundColor: Colors.blue,
      ),
      body: GestureDetector(
        onTap: _handleTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  return _buildMessageBubble(_messages[index]);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textController,
                      decoration: InputDecoration(
                        hintText: 'Enter your message',
                        border: OutlineInputBorder(),
                      ),
                      style: TextStyle(fontSize: 18),
                      onSubmitted: (value) {
                        if (_imageSent) {
                          _sendMessage(value);
                        }
                      },
                    ),
                  ),
                  IconButton(
                    icon: Icon(_isListening ? Icons.mic : Icons.mic_none),
                    onPressed: _listen,
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