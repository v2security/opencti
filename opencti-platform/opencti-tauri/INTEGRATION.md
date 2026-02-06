# OpenCTI Tauri Desktop - Integration Examples

## Frontend Integration Guide

This guide shows how to integrate Tauri-specific features into the existing OpenCTI frontend.

## Basic Platform Detection

```typescript
// Any component
import { isTauri, isWeb } from '@/utils/platform';

function MyComponent() {
  if (isTauri()) {
    // Desktop-specific UI
    return <DesktopToolbar />;
  } else {
    // Web-specific UI
    return <WebToolbar />;
  }
}
```

## Using the Platform Hook

```typescript
import { usePlatform } from '@/utils/platform';

function ExportButton() {
  const { saveFile, showNotification } = usePlatform();
  
  const handleExport = async () => {
    const data = generateReport();
    
    // Works on both desktop and web!
    await saveFile('report.pdf', data, 'application/pdf');
    
    // Show notification
    await showNotification(
      'Export Complete',
      'Report has been saved successfully'
    );
  };
  
  return <button onClick={handleExport}>Export Report</button>;
}
```

## File Operations

### Save File with Native Dialog

```typescript
import { saveFile } from '@/utils/platform';

// Export STIX file
const exportSTIX = async (stixData: string) => {
  await saveFile(
    'export.json',
    stixData,
    'application/json'
  );
};

// Export PDF
const exportPDF = async (pdfBlob: Blob) => {
  await saveFile(
    'report.pdf',
    pdfBlob,
    'application/pdf'
  );
};

// Export CSV
const exportCSV = async (csvContent: string) => {
  await saveFile(
    'data.csv',
    csvContent,
    'text/csv'
  );
};
```

### Open File Picker

```typescript
import { openFile } from '@/utils/platform';

const ImportButton = () => {
  const handleImport = async () => {
    const file = await openFile();
    if (file) {
      const text = new TextDecoder().decode(file.data);
      const json = JSON.parse(text);
      // Process imported data
      processImportedData(json);
    }
  };
  
  return <button onClick={handleImport}>Import STIX</button>;
};
```

## Notifications

```typescript
import { showNotification } from '@/utils/platform';

// Simple notification
await showNotification(
  'New Threat Detected',
  'A high-severity threat has been identified'
);

// In a component
function ThreatMonitor() {
  const handleNewThreat = async (threat: Threat) => {
    await showNotification(
      `New ${threat.severity} Threat`,
      threat.name
    );
  };
  
  // ... rest of component
}
```

## Secure Storage

Replace localStorage with platform-aware storage:

```typescript
import { PlatformStorage } from '@/utils/platform';

// Save user preferences
await PlatformStorage.set('theme', 'dark');

// Get user preferences
const theme = await PlatformStorage.get<string>('theme', 'light');

// Save complex objects
await PlatformStorage.set('userSettings', {
  notifications: true,
  autoSync: false,
  language: 'en'
});

// Get complex objects
const settings = await PlatformStorage.get<UserSettings>('userSettings');

// Remove item
await PlatformStorage.remove('temporaryData');

// Clear all
await PlatformStorage.clear();
```

## Platform Information

```typescript
import { getPlatformInfo } from '@/utils/platform';

const AboutPage = () => {
  const [platformInfo, setPlatformInfo] = useState<any>(null);
  
  useEffect(() => {
    getPlatformInfo().then(setPlatformInfo);
  }, []);
  
  if (!platformInfo) return <Loading />;
  
  return (
    <div>
      <h1>OpenCTI Desktop</h1>
      <p>Platform: {platformInfo.platform}</p>
      <p>Architecture: {platformInfo.arch}</p>
      {platformInfo.version && (
        <p>Version: {platformInfo.version}</p>
      )}
    </div>
  );
};
```

## Conditional Features

### Desktop-only Features

```typescript
import { isTauri } from '@/utils/platform';

function ToolbarActions() {
  return (
    <>
      <ExportButton />
      <ImportButton />
      <ShareButton />
      
      {/* Only show in desktop app */}
      {isTauri() && (
        <>
          <SaveLocallyButton />
          <OfflineModeToggle />
        </>
      )}
    </>
  );
}
```

### Web-only Features

```typescript
import { isWeb } from '@/utils/platform';

function Header() {
  return (
    <header>
      <Logo />
      <Navigation />
      
      {/* Only show in web version */}
      {isWeb() && (
        <DownloadDesktopAppButton />
      )}
    </header>
  );
}
```

## Advanced: Direct Tauri API Usage

For features not covered by the platform utilities:

```typescript
import { invoke } from '@tauri-apps/api/core';
import { isTauri } from '@/utils/platform';

async function customFeature() {
  if (!isTauri()) {
    console.warn('This feature only works in desktop app');
    return;
  }
  
  try {
    // Call custom Rust command
    const result = await invoke('my_custom_command', {
      arg1: 'value1',
      arg2: 42
    });
    console.log('Result:', result);
  } catch (error) {
    console.error('Failed:', error);
  }
}
```

## Migrating Existing Code

### Before (Web-only)

```typescript
const handleExport = () => {
  const blob = new Blob([data], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'export.json';
  a.click();
  URL.revokeObjectURL(url);
};
```

### After (Platform-aware)

```typescript
import { saveFile } from '@/utils/platform';

const handleExport = async () => {
  await saveFile('export.json', data, 'application/json');
};
```

## Best Practices

### 1. Use Platform Utilities

✅ **Good:**
```typescript
import { saveFile } from '@/utils/platform';
await saveFile('data.json', content);
```

❌ **Avoid:**
```typescript
if (window.__TAURI__) {
  // Tauri-specific code
} else {
  // Web-specific code
}
```

### 2. Graceful Degradation

```typescript
const enhancedFeature = async () => {
  try {
    if (isTauri()) {
      // Use native feature
      await invoke('native_operation');
    } else {
      // Fallback to web API
      await webAlternative();
    }
  } catch (error) {
    // Always have a fallback
    console.error('Feature failed:', error);
    showErrorMessage('Operation failed');
  }
};
```

### 3. Type Safety

```typescript
import { PlatformStorage } from '@/utils/platform';

interface UserPreferences {
  theme: 'light' | 'dark';
  language: string;
  notifications: boolean;
}

// Type-safe storage
const prefs = await PlatformStorage.get<UserPreferences>('preferences');
if (prefs) {
  applyTheme(prefs.theme);
}
```

### 4. Error Handling

```typescript
import { showNotification } from '@/utils/platform';

try {
  await riskyOperation();
  await showNotification('Success', 'Operation completed');
} catch (error) {
  await showNotification('Error', error.message);
  logError(error);
}
```

## Testing

### Mock Tauri in Tests

```typescript
// In test setup
global.window.__TAURI__ = {
  invoke: jest.fn(),
  event: {
    listen: jest.fn(),
    emit: jest.fn(),
  },
};

// In test
import { isTauri } from '@/utils/platform';

test('uses desktop features when in Tauri', async () => {
  expect(isTauri()).toBe(true);
  // Test desktop-specific behavior
});
```

## Common Patterns

### Feature Flag

```typescript
const DESKTOP_FEATURES = {
  offlineMode: isTauri(),
  nativeNotifications: isTauri(),
  fileSystemAccess: isTauri(),
  autoUpdates: isTauri(),
};

if (DESKTOP_FEATURES.offlineMode) {
  enableOfflineSync();
}
```

### Conditional Rendering

```tsx
import { isTauri } from '@/utils/platform';

const FeatureToggle = ({ desktop, web }: Props) => (
  isTauri() ? desktop : web
);

// Usage
<FeatureToggle
  desktop={<DesktopWidget />}
  web={<WebWidget />}
/>
```

### Progressive Enhancement

```typescript
const enhancedExport = async () => {
  const data = generateExportData();
  
  // Base functionality (works everywhere)
  console.log('Exporting data...');
  
  // Enhanced functionality (desktop only)
  if (isTauri()) {
    await saveFile('export.json', JSON.stringify(data, null, 2));
    await showNotification('Export Complete', 'File saved to disk');
  } else {
    // Web fallback
    downloadAsFile('export.json', data);
  }
};
```

## Next Steps

1. Review existing frontend code for export/import features
2. Replace browser-specific code with platform utilities
3. Add desktop-enhanced features gradually
4. Test both web and desktop versions
5. Update documentation for users

## Resources

- [Tauri API Documentation](https://tauri.app/v2/reference/javascript/api/)
- [Platform Utils Source](/opencti-front/src/utils/platform.ts)
- [Main Rust Backend](/opencti-tauri/src-tauri/src/main.rs)
