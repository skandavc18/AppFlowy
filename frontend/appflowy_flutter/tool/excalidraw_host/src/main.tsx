import React, { useCallback, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";

import {
  Excalidraw,
  exportToBlob,
  exportToSvg,
  serializeAsJSON,
} from "@excalidraw/excalidraw";
import "@excalidraw/excalidraw/index.css";

type Theme = "light" | "dark";

type HostMessage =
  | { type: "ready" }
  | { type: "change"; scene: string }
  | { type: "scene"; scene: string; requestId?: string }
  | { type: "export"; format: "png" | "svg"; data: string; requestId?: string }
  | { type: "error"; message: string };

declare global {
  interface Window {
    flutter_inappwebview?: {
      callHandler: (name: string, ...args: unknown[]) => Promise<unknown>;
    };
    appflowyExcalidraw?: AppFlowyBridge;
  }
}

interface AppFlowyBridge {
  load(scene: string): void;
  setTheme(theme: Theme): void;
  setViewMode(viewMode: boolean): void;
  requestScene(requestId?: string): void;
  sceneNow(): string;
  exportImage(format: "png" | "svg", requestId?: string): void;
  scrollToContent(): void;
  flush(): void;
}

const HANDLER = "appflowyExcalidraw";

/** Posts a message to the Flutter side, or drops it when running standalone. */
const post = (message: HostMessage) => {
  try {
    window.flutter_inappwebview?.callHandler(HANDLER, message);
  } catch (error) {
    // A failed post must never take the editor down with it.
    console.warn("appflowy bridge unavailable", error);
  }
};

const parseScene = (raw: string) => {
  if (!raw || !raw.trim()) {
    return { elements: [], appState: {}, files: {} };
  }
  try {
    const parsed = JSON.parse(raw);
    return {
      elements: Array.isArray(parsed.elements) ? parsed.elements : [],
      // scrollToContent is applied by hand, and a stored zoom would fight it.
      appState: { ...(parsed.appState ?? {}), collaborators: undefined },
      files: parsed.files ?? {},
    };
  } catch (error) {
    post({ type: "error", message: `Scene could not be read: ${error}` });
    return { elements: [], appState: {}, files: {} };
  }
};

const App = () => {
  const apiRef = useRef<any>(null);
  const [theme, setTheme] = useState<Theme>("light");
  const [viewModeEnabled, setViewMode] = useState(false);
  const changeTimer = useRef<number | undefined>(undefined);
  const lastSent = useRef<string>("");
  const loaded = useRef(false);

  /** Everything the block needs, in the `.excalidraw` shape. */
  const serialize = useCallback(() => {
    const api = apiRef.current;
    if (!api) {
      return "";
    }
    return serializeAsJSON(
      api.getSceneElements(),
      api.getAppState(),
      api.getFiles(),
      "local",
    );
  }, []);

  /** Sends the scene now, rather than on the next pause. */
  const flush = useCallback(() => {
    window.clearTimeout(changeTimer.current);
    const scene = serialize();
    if (scene && scene !== lastSent.current) {
      lastSent.current = scene;
      post({ type: "change", scene });
    }
  }, [serialize]);

  /** Fits the drawing to the viewport, whichever API this build offers. */
  const frameContent = useCallback(() => {
    const api = apiRef.current;
    if (!api) {
      return;
    }
    const elements = api.getSceneElements();
    if (!elements || elements.length === 0) {
      return;
    }
    try {
      if (typeof api.setViewport === "function") {
        api.setViewport({ target: elements, fit: "scale-down" });
      } else if (typeof api.scrollToContent === "function") {
        api.scrollToContent(elements, { fitToContent: true });
      }
    } catch (error) {
      post({ type: "error", message: `Could not frame the drawing: ${error}` });
    }
  }, []);

  const bridge: AppFlowyBridge = {
    load: (scene) => {
      const api = apiRef.current;
      if (!api) {
        return;
      }
      const data = parseScene(scene);
      lastSent.current = scene;
      loaded.current = true;
      api.updateScene({ elements: data.elements });
      if (data.files && Object.keys(data.files).length > 0) {
        api.addFiles(Object.values(data.files));
      }
      window.requestAnimationFrame(frameContent);
    },
    setTheme: (next) => setTheme(next),
    setViewMode: (next) => setViewMode(next),
    requestScene: (requestId) =>
      post({ type: "scene", scene: serialize(), requestId }),
    // Returned rather than posted, so the host can read the drawing even if
    // the message channel is unavailable.
    sceneNow: () => serialize(),
    exportImage: async (format, requestId) => {
      const api = apiRef.current;
      if (!api) {
        return;
      }
      try {
        const elements = api.getSceneElements();
        const appState = { ...api.getAppState(), exportBackground: true };
        const files = api.getFiles();
        if (format === "svg") {
          const svg = await exportToSvg({ elements, appState, files });
          post({
            type: "export",
            format,
            data: new XMLSerializer().serializeToString(svg),
            requestId,
          });
          return;
        }
        const blob = await exportToBlob({
          elements,
          appState,
          files,
          mimeType: "image/png",
          quality: 1,
          exportPadding: 24,
        });
        const reader = new FileReader();
        reader.onloadend = () =>
          post({
            type: "export",
            format,
            data: String(reader.result ?? ""),
            requestId,
          });
        reader.readAsDataURL(blob);
      } catch (error) {
        post({ type: "error", message: `Export failed: ${error}` });
      }
    },
    scrollToContent: frameContent,
    flush,
  };

  useEffect(() => {
    window.appflowyExcalidraw = bridge;
    return () => {
      window.appflowyExcalidraw = undefined;
    };
  });

  // The host may not have installed its message channel by the time the
  // canvas mounts, so readiness is announced until a scene comes back.
  useEffect(() => {
    post({ type: "ready" });
    const timer = window.setInterval(() => {
      if (loaded.current) {
        window.clearInterval(timer);
        return;
      }
      post({ type: "ready" });
    }, 400);
    const stop = window.setTimeout(() => window.clearInterval(timer), 15000);
    return () => {
      window.clearInterval(timer);
      window.clearTimeout(stop);
    };
  }, []);

  // Nothing should be lost because a window went away mid-stroke.
  useEffect(() => {
    const onHide = () => flush();
    window.addEventListener("pagehide", onHide);
    window.addEventListener("beforeunload", onHide);
    document.addEventListener("visibilitychange", onHide);
    return () => {
      window.removeEventListener("pagehide", onHide);
      window.removeEventListener("beforeunload", onHide);
      document.removeEventListener("visibilitychange", onHide);
    };
  }, [flush]);

  const onChange = useCallback(() => {
    window.clearTimeout(changeTimer.current);
    // The host writes to the document, so a burst of strokes must settle into
    // one write rather than sixty.
    changeTimer.current = window.setTimeout(() => {
      const scene = serialize();
      if (scene && scene !== lastSent.current) {
        lastSent.current = scene;
        post({ type: "change", scene });
      }
    }, 400);
  }, [serialize]);

  const onApi = useCallback((api: any) => {
    if (!api) {
      return;
    }
    apiRef.current = api;
    post({ type: "ready" });
  }, []);

  return (
    <Excalidraw
      // The prop is `onExcalidrawAPI` in 0.18; the older name is kept so a
      // future bump in either direction still hands over the API.
      onExcalidrawAPI={onApi}
      excalidrawAPI={onApi}
      theme={theme}
      viewModeEnabled={viewModeEnabled}
      onChange={onChange}
      langCode="en"
      UIOptions={{
        canvasActions: {
          // AppFlowy owns saving, sharing and the document itself.
          loadScene: false,
          saveToActiveFile: false,
          export: false,
          saveAsImage: true,
          toggleTheme: false,
        },
      }}
    />
  );
};

const container = document.getElementById("root");
if (container) {
  createRoot(container).render(<App />);
}
