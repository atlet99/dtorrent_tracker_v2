/// The tracker base event.
class TrackerEventBase {
  final Map _others = {};

  Map get otherInfomationsMap {
    return _others;
  }

  void setInfo(dynamic key, dynamic value) {
    _others[key] = value;
  }

  dynamic removeInfo(dynamic key) {
    return _others.remove(key);
  }
}
