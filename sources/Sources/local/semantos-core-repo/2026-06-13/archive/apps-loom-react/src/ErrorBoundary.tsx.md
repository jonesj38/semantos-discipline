---
source_path: /home/jake/.edwinpai/disciplines/semantos/state/semantos-core-repo/archive/apps-loom-react/src/ErrorBoundary.tsx
source_type: folder
memory_type: semantic_memory
ingested_at: 2026-06-13T06:27:18.931714+00:00
---

# archive/apps-loom-react/src/ErrorBoundary.tsx

```tsx
/**
 * ErrorBoundary — catches render errors and displays a diagnostic panel.
 *
 * Without this, React silently unmounts the entire tree on error,
 * leaving the user with a blank bg-gray-950 screen and no indication
 * of what went wrong.
 */

import { Component, type ReactNode, type ErrorInfo } from 'react';

interface Props {
  children: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

export class ErrorBoundary extends Component<Props, State> {
  constructor(props: Props) {
    super(props);
    this.state = { hasError: false, error: null, errorInfo: null };
  }

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { hasError: true, error };
  }

  componentDidCatch(error: Error, errorInfo: ErrorInfo): void {
    this.setState({ errorInfo });
    console.error('[ErrorBoundary] Uncaught render error:', error, errorInfo);
  }

  render() {
    if (this.state.hasError) {
      return (
        <div style={{
          padding: '2rem',
          maxWidth: '800px',
          margin: '2rem auto',
          fontFamily: 'ui-monospace, monospace',
          color: '#f87171',
          backgroundColor: '#1a1a2e',
          border: '1px solid #f87171',
          borderRadius: '8px',
        }}>
          <h1 style={{ fontSize: '1.25rem', marginBottom: '1rem' }}>
            Workbench Render Error
          </h1>
          <pre style={{
            whiteSpace: 'pre-wrap',
            wordBreak: 'break-word',
            fontSize: '0.875rem',
            lineHeight: '1.5',
            color: '#fca5a5',
          }}>
            {this.state.error?.message}
            {'\n\n'}
            {this.state.error?.stack}
          </pre>
          {this.state.errorInfo && (
            <details style={{ marginTop: '1rem' }}>
              <summary style={{ cursor: 'pointer', color: '#94a3b8' }}>Component Stack</summary>
              <pre style={{
                whiteSpace: 'pre-wrap',
                fontSize: '0.75rem',
                color: '#94a3b8',
                marginTop: '0.5rem',
              }}>
                {this.state.errorInfo.componentStack}
              </pre>
            </details>
          )}
          <button
            onClick={() => this.setState({ hasError: false, error: null, errorInfo: null })}
            style={{
              marginTop: '1rem',
              padding: '0.5rem 1rem',
              backgroundColor: '#3b82f6',
              color: '#fff',
              border: 'none',
              borderRadius: '4px',
              cursor: 'pointer',
              fontSize: '0.875rem',
            }}
          >
            Try Again
          </button>
        </div>
      );
    }

    return this.props.children;
  }
}

```
