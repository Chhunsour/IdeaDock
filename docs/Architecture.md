# Architecture Overview

IdeaDock is architected as a lightweight, native macOS application built with SwiftUI, AppKit, and SwiftData. It prioritizes speed, zero cloud dependencies, complete offline privacy, and native desktop interactions.

## Core Layers

```
┌─────────────────────────────────────────────────────────────────┐
│                           UI Layer                              │
│   CaptureView   •   FloatingIdeaView   •   LibraryView / Editor │
│                   CommandPaletteView                            │
└────────────────────────────────┬────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────┐
│                    Workspace & Coordination                     │
│           WorkspaceState  •  EdgeDockController                 │
│           WindowSupport   •  HotKeyService                      │
└────────────────────────────────┬────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────┐
│                   Domain Services & Ingestion                   │
│      DropReader  •  ContentAnalysis  •  AttachmentService       │
│      CaptureHistory  •  ExportService                           │
└────────────────────────────────┬────────────────────────────────┘
                                 │
┌────────────────────────────────▼────────────────────────────────┐
│                        Persistence Layer                        │
│             IdeaStore (SwiftData ModelContainer)                │
│             Idea  •  IdeaCategory  •  Attachment                │
└─────────────────────────────────────────────────────────────────┘
```

## Architectural Highlights

- **SwiftData Storage**: `IdeaStore` manages local SQLite persistence via SwiftData. Autosave is enabled, and change notifications update all active windows reactively.
- **Floating Windows & Edge Docking**: Windows are managed through AppKit's `NSPanel` with `.nonactivatingPanel` styling, avoiding stealing key focus from full-screen workflows.
- **Global Shortcut Monitoring**: `HotKeyService` leverages Carbon and event taps for instant ⌥Space invocation without background clipboard snooping.
- **Attachment Sandboxing**: Security-scoped bookmarks protect external files, while embedded images are isolated inside the local Application Support container.
