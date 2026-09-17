import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:frontend/data/avatars.dart';
import 'package:frontend/models/my_custom_painter.dart';
import 'package:frontend/models/touch_points.dart';
import 'package:frontend/screens/waiting_lobby_screen.dart';
import 'package:frontend/widgets/player_scoreboard_drawer.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:frontend/screens/final_leaderboard.dart';

class PaintScreen extends StatefulWidget {
  final Map data;
  final String screenFrom;
  const PaintScreen({super.key, required this.data, required this.screenFrom});
  @override
  State<PaintScreen> createState() => _PaintScreenState();
}

class _PaintScreenState extends State<PaintScreen> {
  IO.Socket? socket;
  Color selectedColor = Colors.black;
  double opacity = 1;
  double strokeWidth = 2;
  Map dataOfRoom = {};
  List<TouchPoints?> points = [];
  List<Widget> textBlankWidget = [];
  ScrollController _scrollController = ScrollController();
  List<Map> messages = [];
  final TextEditingController messageController = TextEditingController();
  int guessedUserCtr = 0;
  int _start = 60;
  Timer? _timer;
  var scaffoldKey = GlobalKey<ScaffoldState>();
  List<Map> scoreboard = [];
  bool isTextInputReadOnly = false;
  bool hasGameStarted = false;
  int maxPoints = 0;
  String winner = "";
  bool isShowFinalLeaderboard = false;
  bool get isMyTurn {
    return dataOfRoom['turn']?['socketId'] == socket?.id;
  }

  String get host {
    const productionHost = String.fromEnvironment('BACKEND_URL');
    if (productionHost.isNotEmpty) {
      return productionHost;
    }
    if (kIsWeb) {
      return 'http://localhost:5000';
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000';
    }
    return 'http://localhost:5000';
  }

  @override
  void initState() {
    super.initState();
    socket = IO.io(host, <String, dynamic>{
      'autoConnect': false,
      'transports': ['websocket', 'polling'],
    });
    void startTimer() {
      _timer?.cancel();
      const oneSec = Duration(seconds: 1);
      _timer = Timer.periodic(oneSec, (Timer time) {
        if (_start == 0) {
          if (dataOfRoom['turn']?['socketId'] == socket!.id) {
            socket!.emit('change-turn', dataOfRoom['name']);
          }
          time.cancel();
          _timer = null;
        } else {
          setState(() {
            _start--;
          });
        }
      });
    }

    socket!.onConnect((_) {
      debugPrint('Socket connected: ${socket!.id}');
      if (widget.screenFrom == 'createRoom') {
        socket!.emit('create-game', widget.data);
      } else {
        socket!.emit('join-game', widget.data);
      }
    });

    socket!.on('notCorrectGame', (message) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message.toString()),
          backgroundColor: Colors.red,
        ),
      );

      Navigator.pop(context);
    });

    socket!.on('updateRoom', (roomData) {
      final room = roomData['room'] ?? roomData;

      setState(() {
        dataOfRoom = room;

        scoreboard = [
          for (final player in room['players'])
            {
              'username': player['nickname'],
              'avatarId': player['avatarId'].toString(),
              'points': player['points'].toString(),
            },
        ];
      });

      if (!hasGameStarted && room['isJoin'] != true) {
        hasGameStarted = true;
        _start = 60;
        startTimer();
      }
    });

    socket!.on('points', (point) {
      if (point['socketId'] == socket!.id) {
        return;
      }

      if (point['details'] != null) {
        setState(() {
          points.add(
            TouchPoints(
              paint: Paint()
                ..strokeCap = StrokeCap.round
                ..isAntiAlias = true
                ..color = selectedColor.withValues(alpha: opacity)
                ..strokeWidth = strokeWidth,
              points: Offset(
                point['details']['dx'].toDouble(),
                point['details']['dy'].toDouble(),
              ),
            ),
          );
        });
      } else {
        setState(() {
          points.add(null);
        });
      }
    });

    socket!.on('color-change', (colorString) {
      setState(() {
        selectedColor = Color(int.parse(colorString, radix: 16));
      });
    });

    socket!.on('stroke-width', (value) {
      setState(() {
        strokeWidth = value.toDouble();
      });
    });

    socket!.on('clear-screen', (value) {
      setState(() {
        points.clear();
      });
    });

    socket!.on('message', (data) {
      setState(() {
        messages.add(data);
        guessedUserCtr = data['guessedUserCtr'] ?? 0;
      });
      if (guessedUserCtr == dataOfRoom['players'].length - 1 &&
          dataOfRoom['turn']?['socketId'] == socket!.id) {
        socket!.emit('change-turn', dataOfRoom['name']);
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      });
    });

    socket!.on('closeInput', (data) {
      setState(() {
        isTextInputReadOnly = true;
      });
    });

    socket!.on('updateScore', (data) {
      scoreboard.clear();
      for (int i = 0; i < data['players'].length; i++) {
        scoreboard.add({
          'username': data['players'][i]['nickname'],
          'avatarId': data['players'][i]['avatarId'].toString(),
          'points': data['players'][i]['points'].toString(),
        });
      }
      setState(() {});
    });

    socket!.on('change-turn', (data) {
      final room = data['room'];
      final bool isNewRound = data['isNewRound'];
      final String oldWord = dataOfRoom['word'];
      final String nextPlayer = room['turn']['nickname'];

      if (!mounted) return;

      _timer?.cancel();

      setState(() {
        dataOfRoom = room;
        guessedUserCtr = 0;
        _start = 60;
        points.clear();
        isTextInputReadOnly = false;
      });

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'The word was ',
                    style: TextStyle(
                      fontFamily: 'Unkempt',
                      fontSize: 23,
                      color: Colors.black,
                    ),
                  ),
                  Text(
                    oldWord,
                    style: const TextStyle(
                      fontFamily: 'Unkempt',
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Center(
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                  },
                  child: Text(
                    isNewRound ? 'Next Round' : "$nextPlayer's Turn",
                    style: const TextStyle(
                      fontFamily: 'Unkempt',
                      color: Colors.green,
                      fontSize: 22,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ).then((_) {
        if (!mounted) return;
        startTimer();
      });
    });

    socket!.on('game-finished', (data) {
      _timer?.cancel();
      setState(() {
        scoreboard = [
          for (final player in data['players'])
            {
              'username': player['nickname'],
              'avatarId': player['avatarId'].toString(),
              'points': player['points'].toString(),
            },
        ];
        isShowFinalLeaderboard = true;
      });
    });

    socket!.onDisconnect((_) {
      debugPrint('Socket disconnected');
    });

    socket!.onConnectError((error) {
      debugPrint('Socket connection error: $error');
    });

    socket!.connect();
  }

  @override
  void dispose() {
    _timer?.cancel();
    socket?.disconnect();
    socket?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final height = media.size.height;
    final keyboardHeight = media.viewInsets.bottom;
    final keyboardOpen = keyboardHeight > 0;
    void selectColor() {
      showDialog(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Choose Color'),
            content: SingleChildScrollView(
              child: BlockPicker(
                pickerColor: selectedColor,
                onColorChanged: (color) {
                  final colorString = color.value.toRadixString(16);

                  socket!.emit('color-change', {
                    'color': colorString,
                    'roomName': widget.data['name'],
                  });

                  setState(() {
                    selectedColor = color;
                  });
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: Text('Close', style: TextStyle(color: Colors.red)),
              ),
            ],
          );
        },
      );
    }

    return Scaffold(
      resizeToAvoidBottomInset: true,
      key: scaffoldKey,
      drawer: PlayerScore(scoreboard),
      backgroundColor: Colors.transparent,
      body: dataOfRoom.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : isShowFinalLeaderboard
          ? FinalLeaderboard(scoreboard: scoreboard)
          : dataOfRoom['isJoin'] == true
          ? WaitingLobbyScreen(
              occupancy: int.parse(dataOfRoom['occupancy'].toString()),
              noOfPlayers: dataOfRoom['players'].length,
              lobbyName: dataOfRoom['name'],
              players: dataOfRoom['players'],
            )
          : Stack(
              children: [
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/backgrounddrawingpage.png',
                    fit: BoxFit.cover,
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    SizedBox(height: 8),
                    SizedBox(
                      height: keyboardOpen
                          ? (height - keyboardHeight) * 0.32
                          : height * 0.50,
                      child: Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(left: 10, right: 10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.black, width: 0.2),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black54,
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                        child: GestureDetector(
                          onPanUpdate: isMyTurn
                              ? (details) {
                                  final point = TouchPoints(
                                    paint: Paint()
                                      ..strokeCap = StrokeCap.round
                                      ..isAntiAlias = true
                                      ..color = selectedColor.withValues(
                                        alpha: opacity,
                                      )
                                      ..strokeWidth = strokeWidth,
                                    points: details.localPosition,
                                  );

                                  setState(() {
                                    points.add(point);
                                  });

                                  socket!.emit('paint', {
                                    'details': {
                                      'dx': details.localPosition.dx,
                                      'dy': details.localPosition.dy,
                                    },
                                    'roomName': widget.data['name'],
                                  });
                                }
                              : null,
                          onPanStart: isMyTurn
                              ? (details) {
                                  socket!.emit('paint', {
                                    'details': null,
                                    'roomName': widget.data['name'],
                                  });

                                  final point = TouchPoints(
                                    paint: Paint()
                                      ..strokeCap = StrokeCap.round
                                      ..isAntiAlias = true
                                      ..color = selectedColor.withValues(
                                        alpha: opacity,
                                      )
                                      ..strokeWidth = strokeWidth,
                                    points: details.localPosition,
                                  );

                                  setState(() {
                                    points.add(null);
                                    points.add(point);
                                  });

                                  socket!.emit('paint', {
                                    'details': {
                                      'dx': details.localPosition.dx,
                                      'dy': details.localPosition.dy,
                                    },
                                    'roomName': widget.data['name'],
                                  });
                                }
                              : null,
                          onPanCancel: isMyTurn
                              ? () {
                                  socket!.emit('paint', {
                                    'details': null,
                                    'roomName': widget.data['name'],
                                  });

                                  setState(() {
                                    points.add(null);
                                  });
                                }
                              : null,
                          onPanEnd: isMyTurn
                              ? (details) {
                                  socket!.emit('paint', {
                                    'details': null,
                                    'roomName': widget.data['name'],
                                  });

                                  setState(() {
                                    points.add(null);
                                  });
                                }
                              : null,
                          child: SizedBox.expand(
                            child: CustomPaint(
                              painter: MyCustomPainter(pointsList: points),
                            ),
                          ),
                        ),
                      ),
                    ),
                    dataOfRoom['turn']['socketId'] == socket!.id
                        ? Row(
                            mainAxisAlignment: .spaceEvenly,
                            children: [
                              IconButton(
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  selectColor();
                                },
                                icon: Icon(
                                  Icons.color_lens,
                                  color: Colors.black,
                                  size: 30,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(2, 2),
                                      blurRadius: 3,
                                      color: Colors.black54,
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Slider(
                                  min: 1.0,
                                  max: 10.0,
                                  label: 'Stroke width $strokeWidth',
                                  activeColor: selectedColor,
                                  value: strokeWidth,
                                  onChanged: (double value) {
                                    final map = {
                                      'value': value,
                                      'roomName': widget.data['name'],
                                    };
                                    socket!.emit('stroke-width', map);
                                  },
                                ),
                              ),
                              IconButton(
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  socket!.emit('clear-screen', {
                                    'roomName': widget.data['name'],
                                  });
                                },
                                icon: Icon(
                                  Icons.delete,
                                  color: Colors.red,
                                  size: 30,
                                  shadows: [
                                    Shadow(
                                      offset: Offset(2, 2),
                                      blurRadius: 3,
                                      color: Colors.black54,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Center(
                            child: Text(
                              'Guess the word',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 27,
                                fontFamily: 'Unkempt',
                                shadows: [
                                  Shadow(
                                    offset: Offset(1.5, 1.5),
                                    blurRadius: 1.5,
                                    color: Colors.black,
                                  ),
                                ],
                              ),
                            ),
                          ),
                    dataOfRoom['turn']['socketId'] == socket!.id
                        ? Transform.translate(
                            offset: const Offset(0, -10),
                            child: Center(
                              child: Text(
                                dataOfRoom['word'],
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 27,
                                  fontFamily: 'Unkempt',
                                  shadows: [
                                    Shadow(
                                      offset: Offset(1.5, 1.5),
                                      blurRadius: 1.5,
                                      color: Colors.black,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : Container(),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsetsGeometry.only(
                          left: 10,
                          right: 10,
                          top: 5,
                          bottom: 15,
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.all(Radius.circular(20)),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black54,
                                blurRadius: 6,
                                offset: Offset(0, 2),
                              ),
                            ],
                            color: Colors.white,
                            border: BoxBorder.all(
                              color: Colors.black,
                              width: 0.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: ListView.builder(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.only(bottom: 2),
                                  itemCount: messages.length,
                                  itemBuilder: (context, index) {
                                    final message = messages[index];

                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 4,
                                        horizontal: 15,
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          ClipOval(
                                            child: Image.asset(
                                              getAvatar(
                                                message['avatarId'].toString(),
                                              ).asset,
                                              width: 40,
                                              height: 40,
                                              fit: BoxFit.cover,
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  message['nickname'],
                                                  style: const TextStyle(
                                                    color: Colors.black,
                                                    fontSize: 18,
                                                    fontFamily: 'Unkempt',
                                                    fontWeight: FontWeight.bold,
                                                    shadows: [
                                                      Shadow(
                                                        offset: Offset(
                                                          0.5,
                                                          0.5,
                                                        ),
                                                        blurRadius: 0.5,
                                                        color: Colors.black54,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Text(
                                                  message['message'],
                                                  style: const TextStyle(
                                                    fontFamily: 'Unkempt',
                                                    color: Colors.black,
                                                    fontSize: 15,
                                                    shadows: [
                                                      Shadow(
                                                        offset: Offset(
                                                          0.2,
                                                          0.2,
                                                        ),
                                                        blurRadius: 0.2,
                                                        color: Colors.black54,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ),
                              dataOfRoom['turn'] != null &&
                                      dataOfRoom['turn']['socketId'] !=
                                          socket!.id
                                  ? Align(
                                      alignment: Alignment.bottomCenter,
                                      child: Container(
                                        margin: EdgeInsets.only(
                                          top: 10,
                                          bottom: 15,
                                          left: 15,
                                          right: 15,
                                        ),
                                        child: SizedBox(
                                          width: double.infinity,
                                          child: TextField(
                                            readOnly: isTextInputReadOnly,
                                            controller: messageController,
                                            onSubmitted: (value) {
                                              if (value.trim().isNotEmpty) {
                                                Map map = {
                                                  'username':
                                                      widget.data['nickname'],
                                                  'message': value.trim(),
                                                  'word': dataOfRoom['word'],
                                                  'roomName':
                                                      widget.data['name'],
                                                  'guessedUserCtr':
                                                      guessedUserCtr,
                                                  'totalTime': 60,
                                                  'timeTaken': 60 - _start,
                                                };
                                                socket!.emit('message', map);
                                                messageController.clear();
                                              }
                                            },
                                            style: const TextStyle(
                                              fontFamily: 'Unkempt',
                                              fontSize: 18,
                                              color: Colors.black,
                                            ),
                                            textAlign: TextAlign.center,
                                            decoration: InputDecoration(
                                              hintText: 'Your Guess...',
                                              hintStyle: const TextStyle(
                                                fontFamily: 'Unkempt',
                                                fontSize: 18,
                                                color: Colors.black,
                                              ),
                                              filled: true,
                                              fillColor: Colors.white,
                                              contentPadding:
                                                  const EdgeInsets.symmetric(
                                                    vertical: 14,
                                                  ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                                borderSide: const BorderSide(
                                                  color: Colors.black,
                                                  width: 0.5,
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                                borderSide: const BorderSide(
                                                  color: Colors.black,
                                                  width: 1,
                                                ),
                                              ),
                                            ),
                                            textInputAction:
                                                TextInputAction.done,
                                          ),
                                        ),
                                      ),
                                    )
                                  : Container(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 10, top: 5),
                    child: IconButton(
                      onPressed: () {
                        scaffoldKey.currentState?.openDrawer();
                      },
                      icon: const Icon(
                        Icons.menu,
                        color: Colors.black,
                        size: 27,
                      ),
                    ),
                  ),
                ),
              ],
            ),

      floatingActionButton: Container(
        margin: EdgeInsets.only(bottom: 13, right: 8),
        child: FloatingActionButton(
          onPressed: () {},
          elevation: 7,
          backgroundColor: const Color.fromARGB(255, 255, 230, 91),
          child: Text(
            '$_start',
            style: TextStyle(
              fontFamily: 'Unkempt',
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Colors.lightBlue,
              shadows: [
                Shadow(
                  offset: Offset(0.5, 0.5),
                  blurRadius: 0.5,
                  color: Colors.lightBlue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
