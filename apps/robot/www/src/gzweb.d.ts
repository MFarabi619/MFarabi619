declare module "gzweb" {
  export interface SceneManagerConfig {
    elementId?: string;
    websocketUrl?: string;
    websocketKey?: string;
  }

  export class SceneManager {
    constructor(config?: SceneManagerConfig);
    getConnectionStatus(): string;
    resize(): void;
    snapshot(): void;
    resetView(): void;
    follow(entityName: string): void;
    thirdPersonFollow(entityName: string): void;
    firstPerson(entityName: string): void;
    moveTo(entityName: string): void;
    select(entityName: string): void;
    getModels(): Array<{ name?: string }>;
    disconnect(): void;
    destroy(): void;
  }

  export class AssetViewer {
    constructor(config?: Record<string, unknown>);
  }
}
