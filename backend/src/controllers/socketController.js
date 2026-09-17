import { Room } from "../models/room.js";
import { getWord } from "../services/getWord.js";

export const createGame = async (
  io,
  socket,
  { nickname, avatarId, name, occupancy, maxRounds },
) => {
  try {
    const existingRoom = await Room.findOne({ name });
    if (existingRoom) {
      socket.emit("notCorrectGame", "Room with that name already exists!");
      return;
    }
    const room = await Room.create({
      word: getWord(),
      name,
      occupancy,
      maxRounds,
      players: [
        {
          socketId: socket.id,
          nickname,
          avatarId,
          isPartyLeader: true,
        },
      ],
    });
    room.turn = room.players[0];
    await room.save();
    socket.join(name);
    io.to(name).emit("updateRoom", room);
  } catch (error) {
    console.error(error);
    socket.emit("serverError", "Something went wrong");
  }
};

export const joinGame = async (io, socket, { nickname, avatarId, name }) => {
  try {
    const room = await Room.findOne({ name });
    if (!room) {
      socket.emit("notCorrectGame", "Please enter a valid room name!");
      return;
    }
    if (room.players.length >= room.occupancy) {
      socket.emit("notCorrectGame", "Room is full!");
      return;
    }
    if (!room.isJoin) {
      socket.emit("notCorrectGame", "Game has already started!");
      return;
    }
    const updatedRoom = await Room.findOneAndUpdate(
      { name },
      {
        $push: {
          players: {
            socketId: socket.id,
            nickname,
            avatarId,
          },
        },
      },
      { new: true },
    );
    if (!updatedRoom) {
      socket.emit("notCorrectGame", "Room no longer exists!");
      return;
    }
    if (updatedRoom.players.length >= Number(updatedRoom.occupancy)) {
      updatedRoom.isJoin = false;
    }
    if (!updatedRoom.turn) {
      updatedRoom.turn = updatedRoom.players[updatedRoom.turnIndex];
    }

    await updatedRoom.save();
    socket.join(name);
    io.to(name).emit("updateRoom", updatedRoom);
  } catch (error) {
    console.error(error);
    socket.emit("serverError", "Something went wrong");
  }
};

export const paint = async (io, socket, { details, roomName }) => {
  try {
    const room = await Room.findOne({ name: roomName });
    if (!room) return;
    if (room.turn?.socketId !== socket.id) {
      return;
    }
    io.to(roomName).emit("points", {
      details,
      socketId: socket.id,
    });
  } catch (error) {
    console.error(error);
    socket.emit("serverError", "Something went wrong");
  }
};

export const colorChange = async (io, socket, { color, roomName }) => {
  try {
    io.to(roomName).emit("color-change", color);
  } catch (error) {
    console.error(error);
    socket.emit("serverError", "Something went wrong");
  }
};

export const strokeWidth = async (io, socket, { value, roomName }) => {
  try {
    io.to(roomName).emit("stroke-width", value);
  } catch (error) {
    console.error(error);
    socket.emit("serverError", "Something went wrong");
  }
};

export const clearScreen = async (io, socket, { roomName }) => {
  try {
    io.to(roomName).emit("clear-screen", "");
  } catch (error) {
    console.error(error);
    socket.emit("serverError", "Something went wrong");
  }
};

export const message = async (io, socket, { roomName, message, timeTaken }) => {
  try {
    const room = await Room.findOne({ name: roomName });
    if (!room) return;
    const player = room.players.find((player) => player.socketId === socket.id);
    if (!player) return;
    if (message === room.word) {
      if (player.getUserCtr > 0) {
        return;
      }
      if (timeTaken !== 0) {
        player.points += Math.round((200 / timeTaken) * 10);
      }
      player.getUserCtr = 1;
      await room.save();
      const guessedUserCtr = room.players.filter(
        (player) => player.getUserCtr > 0,
      ).length;
      socket.emit("closeInput");
      io.to(roomName).emit("message", {
        nickname: player.nickname,
        avatarId: player.avatarId,
        message: "Guessed it!",
        guessedUserCtr,
      });

      io.to(roomName).emit("updateScore", room);
    } else {
      io.to(roomName).emit("message", {
        nickname: player.nickname,
        avatarId: player.avatarId,
        message,
        guessedUserCtr: player.getUserCtr,
      });
    }
  } catch (error) {
    console.error(error);
    socket.emit("serverError", "Something went wrong");
  }
};

export const changeTurn = async (io, socket, name) => {
  try {
    const room = await Room.findOne({ name });
    if (!room || room.players.length === 0) {
      return;
    }
    if (room.turn?.socketId !== socket.id) {
      return;
    }
    if (room.isChangingTurn) {
      return;
    }
    room.isChangingTurn = true;
    await room.save();
    const nextIndex = (room.turnIndex + 1) % room.players.length;
    if (nextIndex === 0) {
      room.currentRound += 1;
    }
    if (room.currentRound > room.maxRounds) {
      room.isChangingTurn = false;
      await room.save();
      io.to(name).emit("game-finished", {
        word: room.word,
        players: room.players,
      });
      await Room.deleteOne({ _id: room._id });
      return;
    }
    const isNewRound = nextIndex === 0;
    room.turnIndex = nextIndex;
    room.turn = room.players[nextIndex];
    room.word = getWord();
    room.players.forEach((player) => {
      player.getUserCtr = 0;
    });
    room.isChangingTurn = false;
    await room.save();
    io.to(name).emit("change-turn", {
      room,
      isNewRound,
    });
  } catch (error) {
    console.error(error);
    socket.emit("serverError", "Something went wrong");
  }
};

export const updateScore = async (io, socket, name) => {
  try {
    const room = await Room.findOne({ name });
    io.to(name).emit("updateScore", room);
  } catch (error) {
    console.error(error);
    socket.emit("serverError", "Something went wrong");
  }
};

export const disconnect = async (socket) => {
  console.log("User disconnected:", socket.id);
  try {
    const room = await Room.findOne({
      "players.socketId": socket.id,
    });
    if (!room) return;
    const playerIndex = room.players.findIndex(
      (player) => player.socketId === socket.id,
    );
    if (playerIndex === -1) return;
    const wasCurrentTurn = room.turn?.socketId === socket.id;
    room.players.splice(playerIndex, 1);
    if (room.players.length === 0) {
      await Room.deleteOne({ _id: room._id });
      return;
    }
    if (playerIndex < room.turnIndex) {
      room.turnIndex--;
    }
    room.turnIndex = room.turnIndex % room.players.length;
    if (wasCurrentTurn) {
      room.turn = room.players[room.turnIndex];
      room.word = getWord();

      room.players.forEach((player) => {
        player.getUserCtr = 0;
      });
    }
    await room.save();
    io.to(room.name).emit("updateRoom", room);
    if (wasCurrentTurn) {
      io.to(room.name).emit("change-turn", {
        room,
        isNewRound: false,
      });
    }
  } catch (error) {
    console.error("Disconnect error:", error);
  }
};
