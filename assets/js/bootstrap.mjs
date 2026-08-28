const socketOptions = {
  params: { _csrf_token: csrfToken },
  hooks: {
    BeamConsoleCharts,
    BeamConsoleGraph,
    BeamConsolePanels,
    BeamConsoleTheme,
    BeamConsoleTree
  }
};
if (transport === "longpoll") socketOptions.transport = LongPoll;
const liveSocket = new LiveSocket(livePath, Socket, socketOptions);
liveSocket.connect();
window.beamConsoleLiveSocket = liveSocket;
