import 'package:cloud_firestore/cloud_firestore.dart';

class Conversation {
  String? id;
  String imageUrl;
  String imageDescription;
  List<Message> messages;
  DateTime timestamp;
  bool isVideo; // New field

  Conversation({
    this.id,
    required this.imageUrl,
    required this.imageDescription,
    required this.messages,
    required this.timestamp,
    this.isVideo = false, // Default to false for existing conversations
  });

  Map<String, dynamic> toMap() {
    return {
      'imageUrl': imageUrl,
      'imageDescription': imageDescription,
      'messages': messages.map((message) => message.toMap()).toList(),
      'timestamp': Timestamp.fromDate(timestamp),
      'isVideo': isVideo, // Include isVideo in the map
    };
  }

  factory Conversation.fromMap(Map<String, dynamic> map) {
    return Conversation(
      id: map['id'],
      imageUrl: map['imageUrl'] ?? '',
      imageDescription: map['imageDescription'] ?? '',
      messages: List<Message>.from(
        (map['messages'] ?? []).map(
          (messageData) => Message.fromMap(messageData),
        ),
      ),
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      isVideo: map['isVideo'] ?? false, // Read isVideo from the map, default to false if not present
    );
  }
}

class Message {
  String sender; // 'user' or 'model'
  String text;

  Message({
    required this.sender,
    required this.text,
  });

  Map<String, dynamic> toMap() {
    return {
      'sender': sender,
      'text': text,
    };
  }

  factory Message.fromMap(Map<String, dynamic> map) {
    return Message(
      sender: map['sender'] ?? '',
      text: map['text'] ?? '',
    );
  }
}