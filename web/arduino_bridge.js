//arduino_bridge.js
let port;
let writer;
document.getElementById('connectBtn')?.addEventListener('click', () => {
  if (window.connectUSB) window.connectUSB();
});

window.connectUSB = async function() {
  try {
    port = await navigator.serial.requestPort();
    await port.open({ baudRate: 9600 });

    const decoder = new TextDecoderStream();
    const readableStreamClosed = port.readable.pipeTo(decoder.writable);
    const reader = decoder.readable.getReader();

    const encoder = new TextEncoderStream();
    const writableStreamClosed = encoder.readable.pipeTo(port.writable);
    writer = encoder.writable.getWriter();

    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      if (value.trim() === "STRIKE") window.postMessage("STRIKE");
      if (value.trim() === "OK") window.postMessage("OK");
    }
  } catch (err) {
    console.error("USB connection error:", err);
  }
};

window.sendToArduino = async function(msg) {
  if (writer) await writer.write(msg + "\n");
};
