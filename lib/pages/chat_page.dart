import 'package:chat_gpt_sdk/chat_gpt_sdk.dart';
import 'package:dash_chat_2/dash_chat_2.dart';
import 'package:flutter/material.dart';
import 'package:rtc_link/consts.dart'; // OPEN_API_KEY

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late OpenAI _openAI;

  final ChatUser _currentuser =
  ChatUser(id: '1', firstName: "Vaibhav", lastName: "Joshi");
  final ChatUser _gptchatUser =
  ChatUser(id: '2', firstName: "Chat", lastName: "GPT");

  List<ChatMessage> _message = <ChatMessage>[];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _openAI = OpenAI.instance.build(
      token: OPEN_API_KEY,
      baseOption: HttpSetup(receiveTimeout: const Duration(seconds: 5)),
      enableLog: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xff008665),
        title: const Text(
          "VaibAssist",
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        centerTitle: true,
        toolbarHeight: 50,
      ),
      body: Stack(
        children: [
          DashChat(
            currentUser: _currentuser,
            messageOptions: MessageOptions(
              currentUserContainerColor: Colors.black54,
              containerColor: const Color(0xff008665),
              textColor: Colors.white,
            ),
            onSend: (ChatMessage m) {
              getChatResponse(m);
            },
            messages: _message,
          ),
          if (_isLoading)
            const Positioned(
              bottom: 80,
              left: 0,
              right: 0,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  Future<void> getChatResponse(ChatMessage m) async {
    setState(() {
      _message.insert(0, m);
      _isLoading = true;
    });

    // Map chat history
    List<Messages?> _messageHistory = _message.reversed.map((msg) {
      if (msg.user == _currentuser) {
        return Messages(role: Role.user, content: msg.text);
      } else if (msg.user == _gptchatUser) {
        return Messages(role: Role.assistant, content: msg.text);
      }
      return null;
    }).toList();

    // Remove nulls and convert to Map
    final messageMaps = _messageHistory
        .where((msg) => msg != null)
        .map((msg) => msg!.toJson())
        .toList();

    final request = ChatCompleteText(
      model: GptTurboChatModel(), // You can change to ChatModel.gptTurbo
      messages: messageMaps,
      maxToken: 200,
    );

    try {
      final response = await _openAI.onChatCompletion(request: request);

      if (response == null || response.choices.isEmpty) {
        print("⚠️ No response received from GPT");
        return;
      }

      for (var element in response.choices) {
        print("✅ GPT Response: ${element.message?.content}");

        if (element.message != null) {
          setState(() {
            _message.insert(
              0,
              ChatMessage(
                user: _gptchatUser,
                createdAt: DateTime.now(),
                text: element.message!.content,
              ),
            );
          });
        }
      }
    } catch (e) {
      print("❌ Error getting GPT response: $e");
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }
}
