# System Architecture

Сервис построен вокруг цепочки `API Gateway -> Ingestion Service -> Decryption and Mapping Engine -> Usage Metering`. Он принимает BLE-пакет от клиентского приложения, валидирует запрос, сопоставляет динамические идентификаторы с региональным справочником и возвращает уточнённую координату. Параллельно формируются usage-события для биллинга и операционного мониторинга.

## Диаграмма взаимодействия

```mermaid
flowchart LR
    subgraph Client["1. Приложение клиента"]
        A["BLE scan + POST /v1/location/refine"]
    end

    subgraph Service["Partner Service"]
        B["API Gateway"]
        C["Ingestion Service"]
        D["Decryption and Mapping Engine"]
        E["Usage Metering"]
    end

    subgraph Billing["2. Биллинг партнёра"]
        F["Usage Aggregator"]
        G["Billing API / invoices / webhooks"]
    end

    subgraph Management["3. Управление сервисом"]
        H["Registry Management"]
        I["Audit Logs"]
        J["Partner and Key Management"]
    end

    A --> B --> C --> D
    D --> E --> F --> G
    H --> D
    J --> B
    I --> B
    I --> C
    I --> D
```

## Основные компоненты

- `API Gateway` отвечает за аутентификацию, маршрутизацию и rate limiting.
- `Ingestion Service` валидирует payload, временное окно и технические ограничения запроса.
- `Decryption and Mapping Engine` дешифрует динамические идентификаторы и получает объект из справочника.
- `Usage Metering` публикует агрегируемые события для квотирования и биллинга.
- `Monitoring and Audit` собирает метрики, трейсы и журналы доступа.
