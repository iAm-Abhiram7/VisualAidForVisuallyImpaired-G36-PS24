import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'login.dart';
import 'chat_screen.dart';

class ImagePickerScreen extends StatefulWidget {
  const ImagePickerScreen({super.key});

  @override
  State<ImagePickerScreen> createState() => _ImagePickerScreenState();
}

class _ImagePickerScreenState extends State<ImagePickerScreen> {
  File? selectedFile;
  final picker = ImagePicker();
  final String _description = '';
  bool isVideo = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color.fromARGB(255, 247, 247, 247),
      appBar: AppBar(
        title: const Text(
          'Media Picker',
          style: TextStyle(fontSize: 24),
        ),
        backgroundColor: Colors.blue,
        actions: [
          IconButton(
            onPressed: () async {
              await GoogleSignIn().signOut();
              FirebaseAuth.instance.signOut();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => LoginPage()),
              );
            },
            icon: Icon(Icons.power_settings_new),
          ),
        ],
      ),
      body: GestureDetector(
        onTapUp: (details) {
          final screenWidth = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx > screenWidth / 2) {
            // Tap on the right side, open the camera for image
            _pickMedia(ImageSource.camera, false);
          } else {
            // Tap on the left side, open the camera for video
            _pickMedia(ImageSource.camera, true);
          }
        },
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_description.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Text(
                    _description,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black, fontSize: 18),
                  ),
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.video_library, size: 50),
                        onPressed: () => _pickMedia(ImageSource.gallery, true),
                        tooltip: 'Pick a video from the gallery',
                      ),
                      Text('Gallery Video'),
                    ],
                  ),
                  Column(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.photo_library, size: 50),
                        onPressed: () => _pickMedia(ImageSource.gallery, false),
                        tooltip: 'Pick an image from the gallery',
                      ),
                      Text('Gallery Image'),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 30),
              SizedBox(
                height: 300.0,
                width: 300.0,
                child: selectedFile == null
                    ? const Center(
                        child: Text(
                          'No media selected!',
                          style: TextStyle(color: Colors.black, fontSize: 20),
                        ),
                      )
                    : isVideo
                        ? Center(
                            child: Icon(Icons.video_file, size: 100),
                          )
                        : Image.file(
                            selectedFile!,
                            semanticLabel: 'Selected image',
                            fit: BoxFit.cover,
                          ),
              ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Text('Tap left side for video', style: TextStyle(fontSize: 16)),
                  Text('Tap right side for image', style: TextStyle(fontSize: 16)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickMedia(ImageSource source, bool isVideo) async {
    final XFile? pickedFile = isVideo
        ? await picker.pickVideo(source: source)
        : await picker.pickImage(source: source);

    if (pickedFile != null) {
      setState(() {
        selectedFile = File(pickedFile.path);
        this.isVideo = isVideo;
      });

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            mediaFile: selectedFile!,
            isVideo: isVideo,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No media selected')),
      );
    }
  }
}