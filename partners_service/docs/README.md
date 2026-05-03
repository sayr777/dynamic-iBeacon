# Карта документации партнёрского сервиса

Это основная карта документации по партнёрскому сервису. Разделы покрывают продуктовый, технический, операционный, коммерческий и юридический контуры.

```text
docs/
├── 00-governance/
│   ├── README.md
│   ├── document-map.md
│   └── glossary.md
├── 01-product/
│   ├── README.md
│   ├── service-overview.md
│   ├── roadmap.md
│   └── risks-and-kpis.md
├── 02-architecture/
│   ├── README.md
│   ├── system-architecture.md
│   ├── component-contracts.md
│   └── rnis-isolation-plan.md
├── 03-security/
│   ├── README.md
│   ├── security-model.md
│   ├── key-management.md
│   └── compliance.md
├── 04-api/
│   ├── README.md
│   ├── location-refine-api.md
│   ├── schemas-and-errors.md
│   ├── auth-and-rate-limits.md
│   └── openapi/
│       └── client-service/
│           └── openapi.yaml
├── 05-partner-integration/
│   ├── README.md
│   ├── onboarding.md
│   ├── sdk-guides.md
│   └── troubleshooting.md
├── 06-sandbox/
│   ├── README.md
│   ├── sandbox-overview.md
│   ├── test-data.md
│   └── launch-checklist.md
├── 07-billing/
│   ├── README.md
│   ├── billing-architecture.md
│   ├── billing-api.md
│   ├── quota-and-webhooks.md
│   └── openapi/
│       └── partner-billing/
│           └── openapi.yaml
├── 08-operations/
│   ├── README.md
│   ├── sla.md
│   ├── observability.md
│   ├── service-management.md
│   ├── support-runbook.md
│   └── openapi/
│       └── service-management/
│           └── openapi.yaml
├── 09-commercial/
│   ├── README.md
│   ├── pricing.md
│   └── packaging.md
├── 10-finance/
│   ├── README.md
│   ├── roi-model.md
│   ├── unit-economics.md
│   └── spreadsheet-model.md
├── 11-legal-and-public-sector/
│   ├── README.md
│   ├── contract-package.md
│   ├── procurement-44fz.md
│   └── grant-package.md
└── 12-enablement/
    ├── README.md
    ├── presentation-outline.md
    ├── pilot-checklist.md
    └── partner-faq.md
```

## Покрытие тем

- [01-product](C:\T1_GIT\ble-tag-jdy23-dynamic\partners_service\docs\01-product\README.md) — ценность сервиса, roadmap, KPI и риски
- [02-architecture](C:\T1_GIT\ble-tag-jdy23-dynamic\partners_service\docs\02-architecture\README.md) — компоненты, контракты и интеграция с РНИС
- [03-security](C:\T1_GIT\ble-tag-jdy23-dynamic\partners_service\docs\03-security\README.md) — модель угроз, ключи, требования compliance
- [04-api](C:\T1_GIT\ble-tag-jdy23-dynamic\partners_service\docs\04-api\README.md) — публичный API клиентского приложения и спецификация OpenAPI 3.0.0
- [05-partner-integration](C:\T1_GIT\ble-tag-jdy23-dynamic\partners_service\docs\05-partner-integration\README.md) — onboarding, SDK и типовые интеграционные сценарии
- [06-sandbox](C:\T1_GIT\ble-tag-jdy23-dynamic\partners_service\docs\06-sandbox\README.md) — тестовый контур, данные и чеклист запуска
- [07-billing](C:\T1_GIT\ble-tag-jdy23-dynamic\partners_service\docs\07-billing\README.md) — usage, квоты, `client_id`, вебхуки и счета
- [08-operations](C:\T1_GIT\ble-tag-jdy23-dynamic\partners_service\docs\08-operations\README.md) — SLA, мониторинг, администрирование и поддержка
- [09-commercial](C:\T1_GIT\ble-tag-jdy23-dynamic\partners_service\docs\09-commercial\README.md) — тарифы и упаковка продукта
- [10-finance](C:\T1_GIT\ble-tag-jdy23-dynamic\partners_service\docs\10-finance\README.md) — ROI, юнит-экономика и структура финансовой модели
- [11-legal-and-public-sector](C:\T1_GIT\ble-tag-jdy23-dynamic\partners_service\docs\11-legal-and-public-sector\README.md) — договоры, 44-ФЗ и грантовый пакет
- [12-enablement](C:\T1_GIT\ble-tag-jdy23-dynamic\partners_service\docs\12-enablement\README.md) — пилоты, FAQ и презентационные материалы
