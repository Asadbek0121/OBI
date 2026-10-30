import 'dart:async';
import 'package:flutter/material.dart';
import '../database/database_helper.dart';

class NotificationModel {
  final int? id;
  final String title;
  final String message;
  final String type;
  final DateTime createdAt;
  bool isRead;

  NotificationModel({
    this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.createdAt,
    this.isRead = false,
  });

  factory NotificationModel.fromMap(Map<String, dynamic> map) {
    return NotificationModel(
      id: map['id'],
      title: map['title'],
      message: map['message'],
      type: map['type'],
      createdAt: DateTime.parse(map['created_at']),
      isRead: map['is_read'] == 1,
    );
  }
}

class NotificationProvider extends ChangeNotifier {
  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;

  List<NotificationModel> get notifications => _notifications;
  int get unreadCount => _unreadCount;

  NotificationProvider() {
    refresh();
  }

  Future<void> refresh() async {
    final data = await DatabaseHelper.instance.getNotifications();
    _notifications = data.map((e) => NotificationModel.fromMap(e)).toList();
    _unreadCount = await DatabaseHelper.instance.getUnreadNotificationCount();
    notifyListeners();
  }

  Future<void> addNotification({
    required String title,
    required String message,
    required String type,
  }) async {
    await DatabaseHelper.instance.insertNotification({
      'title': title,
      'message': message,
      'type': type,
    });
    await refresh();
  }

  Future<void> markAsRead(int id) async {
    await DatabaseHelper.instance.markNotificationAsRead(id);
    await refresh();
  }

  Future<void> markAllAsRead() async {
    await DatabaseHelper.instance.markAllNotificationsAsRead();
    await refresh();
  }

  Future<void> clearAll() async {
    await DatabaseHelper.instance.clearAllNotifications();
    await refresh();
  }
}
