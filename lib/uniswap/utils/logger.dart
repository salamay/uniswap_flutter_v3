import 'package:flutter/cupertino.dart';

void logger(String message,String className) {
  debugPrint("[$className]: $message");
}