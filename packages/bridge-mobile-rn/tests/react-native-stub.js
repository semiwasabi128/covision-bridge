module.exports = {
  WebSocket: globalThis.WebSocket,
  AppRegistry: { registerComponent: () => undefined },
  StyleSheet: { create: function(x) { return x; }, flatten: function(x) { return x; } },
  Platform: { OS: 'ios' }
};
