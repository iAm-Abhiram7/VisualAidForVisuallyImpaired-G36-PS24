import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_1/components/conversation_model.dart';
import 'chat_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:video_player/video_player.dart';

class ChatHistoryScreen extends StatefulWidget {
  @override
  _ChatHistoryScreenState createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  List<Conversation> conversations = [];
  String? currentUserId;
  Map<String, VideoPlayerController> videoControllers = {};

  @override
  void initState() {
    super.initState();
    _getCurrentUser();
  }

  @override
  void dispose() {
    for (var controller in videoControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _getCurrentUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        currentUserId = user.uid;
      });
      _getConversations();
    }
  }

  Future<void> _getConversations() async {
    if (currentUserId == null) return;
    final conversationsSnapshot = await FirebaseFirestore.instance
        .collection('conversations')
        .orderBy('timestamp', descending: true)
        .get();
    final conversationsList = conversationsSnapshot.docs.map((doc) {
      final conversationData = doc.data();
      return Conversation.fromMap({...conversationData, 'id': doc.id});
    }).toList();

    setState(() {
      conversations = conversationsList;
    });

    for (var conversation in conversations) {
      if (conversation.isVideo) {
        _initializeVideoController(conversation.id!, conversation.imageUrl);
      }
    }
  }

  void _initializeVideoController(String id, String videoUrl) {
    final controller = VideoPlayerController.file(File(videoUrl));
    videoControllers[id] = controller;
    controller.initialize().then((_) {
      setState(() {});
    });
  }

  Future<void> _deleteConversation(String? conversationId) async {
    if (conversationId == null) {
      return;
    }
    await FirebaseFirestore.instance
        .collection('conversations')
        .doc(conversationId)
        .delete();
    if (videoControllers.containsKey(conversationId)) {
      await videoControllers[conversationId]!.dispose();
      videoControllers.remove(conversationId);
    }
    _getConversations(); // Refresh the list after deletion
  }

  Widget _buildMediaWidget(String mediaUrl, bool isVideo, String? conversationId) {
    if (isVideo) {
      if (conversationId != null && videoControllers.containsKey(conversationId)) {
        final controller = videoControllers[conversationId]!;
        if (controller.value.isInitialized) {
          return SizedBox(
            width: 60,
            height: 60,
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: VideoPlayer(controller),
            ),
          );
        }
      }
      return Container(
        width: 60,
        height: 60,
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    } else {
      if (mediaUrl.startsWith('http://') || mediaUrl.startsWith('https://')) {
        // Network image
        return Image.network(
          mediaUrl,
          width: 60,
          height: 60,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Container(
              width: 60,
              height: 60,
              color: Colors.grey[300],
              child: Icon(Icons.error, color: Colors.red),
            );
          },
        );
      } else {
        // Local file
        final file = File(mediaUrl);
        if (file.existsSync()) {
          return Image.file(
            file,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 60,
                height: 60,
                color: Colors.grey[300],
                child: Icon(Icons.error, color: Colors.red),
              );
            },
          );
        } else {
          // If file doesn't exist, try to load from assets
          return Image.asset(
            mediaUrl,
            width: 60,
            height: 60,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Container(
                width: 60,
                height: 60,
                color: Colors.grey[300],
                child: Icon(Icons.error, color: Colors.red),
              );
            },
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat History', style: TextStyle(color: Colors.black87)),
        backgroundColor: Colors.white,
        elevation: 1,
      ),
      body: ListView.builder(
        itemCount: conversations.length,
        itemBuilder: (context, index) {
          final conversation = conversations[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExpansionTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildMediaWidget(conversation.imageUrl, conversation.isVideo, conversation.id),
                ),
                title: Text(
                  conversation.imageDescription,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Messages: ${conversation.messages.length} | ${conversation.isVideo ? 'Video' : 'Image'}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                ),
                children: [
                  ...conversation.messages.map((message) => Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
                        child: ListTile(
                          title: Text(
                            message.sender == 'user' ? 'You' : 'AI',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(message.text),
                          tileColor: message.sender == 'user' ? Colors.blue[50] : Colors.grey[100],
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      )),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton(
                          child: Text(
                            'Continue this conversation',
                            style: TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.lightBlue,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ChatScreen(
                                  mediaFile: File(conversation.imageUrl),
                                  conversationId: conversation.id,
                                  isVideo: conversation.isVideo,
                                ),
                              ),
                            );
                          },
                        ),
                        ElevatedButton(
                          child: Text(
                            'Delete',
                            style: TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text("Delete Conversation"),
                                  content: Text("Are you sure you want to delete this conversation?"),
                                  actions: [
                                    TextButton(
                                      child: Text("Cancel"),
                                      onPressed: () {
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                    TextButton(
                                      child: Text("Delete"),
                                      onPressed: () {
                                        _deleteConversation(conversation.id);
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}