/**
 * Platform Detection and Tauri Integration Utilities
 * 
 * This module provides utilities to detect if the app is running in Tauri (desktop)
 * or in a web browser, and provides unified APIs for cross-platform features.
 */

// Type definitions for Tauri API (to avoid full import in web builds)
declare global {
  interface Window {
    __TAURI__?: {
      invoke: (cmd: string, args?: Record<string, unknown>) => Promise<unknown>;
      event: {
        listen: (event: string, handler: (event: unknown) => void) => Promise<() => void>;
        emit: (event: string, payload?: unknown) => Promise<void>;
      };
    };
  }
}

/**
 * Check if the app is running in Tauri (desktop mode)
 */
export const isTauri = (): boolean => {
  return typeof window !== 'undefined' && window.__TAURI__ !== undefined;
};

/**
 * Check if the app is running in a web browser
 */
export const isWeb = (): boolean => {
  return !isTauri();
};

/**
 * Get platform information
 */
export const getPlatform = (): 'desktop' | 'web' => {
  return isTauri() ? 'desktop' : 'web';
};

/**
 * Platform-aware file download/save
 * In Tauri: Uses native save dialog
 * In Web: Triggers browser download
 */
export const saveFile = async (
  filename: string,
  content: Blob | ArrayBuffer | string,
  mimeType = 'application/octet-stream'
): Promise<void> => {
  if (isTauri()) {
    // Convert content to Uint8Array
    let bytes: Uint8Array;
    if (content instanceof Blob) {
      const arrayBuffer = await content.arrayBuffer();
      bytes = new Uint8Array(arrayBuffer);
    } else if (content instanceof ArrayBuffer) {
      bytes = new Uint8Array(content);
    } else {
      bytes = new TextEncoder().encode(content);
    }

    // Use Tauri's native save dialog
    const { invoke } = await import('@tauri-apps/api/core');
    await invoke('save_export', {
      filename,
      content: Array.from(bytes),
    });
  } else {
    // Web fallback: trigger download
    const blob = content instanceof Blob 
      ? content 
      : content instanceof ArrayBuffer
        ? new Blob([content], { type: mimeType })
        : new Blob([content], { type: mimeType });
    
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = filename;
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }
};

/**
 * Platform-aware file picker
 * In Tauri: Uses native open dialog
 * In Web: Uses file input
 */
export const openFile = async (): Promise<{ name: string; data: ArrayBuffer } | null> => {
  if (isTauri()) {
    const { invoke } = await import('@tauri-apps/api/core');
    try {
      const [filename, content] = await invoke('open_file') as [string, number[]];
      return {
        name: filename,
        data: new Uint8Array(content).buffer,
      };
    } catch (error) {
      console.error('Failed to open file:', error);
      return null;
    }
  } else {
    // Web fallback: file input
    return new Promise((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.onchange = async (e) => {
        const file = (e.target as HTMLInputElement).files?.[0];
        if (file) {
          const data = await file.arrayBuffer();
          resolve({ name: file.name, data });
        } else {
          resolve(null);
        }
      };
      input.click();
    });
  }
};

/**
 * Platform-aware notifications
 * In Tauri: Uses native OS notifications
 * In Web: Uses browser notifications API
 */
export const showNotification = async (
  title: string,
  body: string,
  options?: NotificationOptions
): Promise<void> => {
  if (isTauri()) {
    const { invoke } = await import('@tauri-apps/api/core');
    await invoke('show_notification', { title, body });
  } else {
    // Web fallback
    if ('Notification' in window) {
      if (Notification.permission === 'granted') {
        new Notification(title, { body, ...options });
      } else if (Notification.permission !== 'denied') {
        const permission = await Notification.requestPermission();
        if (permission === 'granted') {
          new Notification(title, { body, ...options });
        }
      }
    }
  }
};

/**
 * Get platform-specific information
 */
export const getPlatformInfo = async (): Promise<{
  platform: string;
  arch: string;
  isDesktop: boolean;
  version?: string;
}> => {
  if (isTauri()) {
    const { invoke } = await import('@tauri-apps/api/core');
    const info = await invoke('get_platform_info') as {
      platform: string;
      arch: string;
      is_desktop: boolean;
      version: string;
    };
    return {
      platform: info.platform,
      arch: info.arch,
      isDesktop: info.is_desktop,
      version: info.version,
    };
  } else {
    return {
      platform: 'web',
      arch: navigator.userAgent.includes('x64') ? 'x86_64' : 'unknown',
      isDesktop: false,
    };
  }
};

/**
 * Storage wrapper that uses secure storage in Tauri
 * In Tauri: Uses encrypted store
 * In Web: Uses localStorage
 */
export class PlatformStorage {
  private static tauriStore: unknown = null;

  private static async getTauriStore() {
    if (!this.tauriStore) {
      const { Store } = await import('@tauri-apps/plugin-store');
      this.tauriStore = new Store('opencti-store.bin');
    }
    return this.tauriStore as {
      get: (key: string) => Promise<unknown>;
      set: (key: string, value: unknown) => Promise<void>;
      delete: (key: string) => Promise<boolean>;
      clear: () => Promise<void>;
      save: () => Promise<void>;
    };
  }

  static async get<T>(key: string, defaultValue?: T): Promise<T | null> {
    if (isTauri()) {
      const store = await this.getTauriStore();
      const value = await store.get(key);
      return value !== undefined ? (value as T) : (defaultValue ?? null);
    } else {
      const value = localStorage.getItem(key);
      if (value === null) return defaultValue ?? null;
      try {
        return JSON.parse(value) as T;
      } catch {
        return value as T;
      }
    }
  }

  static async set<T>(key: string, value: T): Promise<void> {
    if (isTauri()) {
      const store = await this.getTauriStore();
      await store.set(key, value);
      await store.save();
    } else {
      const stringValue = typeof value === 'string' ? value : JSON.stringify(value);
      localStorage.setItem(key, stringValue);
    }
  }

  static async remove(key: string): Promise<void> {
    if (isTauri()) {
      const store = await this.getTauriStore();
      await store.delete(key);
      await store.save();
    } else {
      localStorage.removeItem(key);
    }
  }

  static async clear(): Promise<void> {
    if (isTauri()) {
      const store = await this.getTauriStore();
      await store.clear();
      await store.save();
    } else {
      localStorage.clear();
    }
  }
}

/**
 * Hook to use in React components
 */
export const usePlatform = () => {
  return {
    isTauri: isTauri(),
    isWeb: isWeb(),
    platform: getPlatform(),
    saveFile,
    openFile,
    showNotification,
    getPlatformInfo,
    storage: PlatformStorage,
  };
};
