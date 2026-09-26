const TYPES = ['video/mp4;codecs=avc1', 'video/mp4', 'video/webm;codecs=vp9', 'video/webm;codecs=vp8', 'video/webm']

export function videoSupported() {
  return typeof MediaRecorder !== 'undefined' && TYPES.some((t) => MediaRecorder.isTypeSupported(t))
}

export function recordCanvas(canvas: HTMLCanvasElement, fps = 30) {
  const type = TYPES.find((t) => MediaRecorder.isTypeSupported(t))
  if (!type) return null
  const stream = canvas.captureStream(fps)
  const recorder = new MediaRecorder(stream, { mimeType: type, videoBitsPerSecond: 6_000_000 })
  const chunks: Blob[] = []
  recorder.ondataavailable = (e) => e.data.size && chunks.push(e.data)
  recorder.start(250)
  return {
    ext: type.startsWith('video/mp4') ? 'mp4' : 'webm',
    stop: () =>
      new Promise<Blob>((resolve) => {
        recorder.onstop = () => {
          stream.getTracks().forEach((t) => t.stop())
          resolve(new Blob(chunks, { type: type.split(';')[0] }))
        }
        recorder.stop()
      }),
  }
}
