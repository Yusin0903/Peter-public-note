/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  tutorialSidebar: [
    'intro',
    {
      type: 'category',
      label: 'AWS',
      items: [
        'aws/self-managed-vs-fully-managed',
        'aws/dynamodb-no-connection-pool',
        'aws/service-token-dynamodb',
        'aws/sqs-client-and-md5',
        'aws/sqs-polling-and-vs-rabbitmq',
      ],
    },
    {
      type: 'category',
      label: 'JavaScript / TypeScript',
      items: [
        'javascript/export-import',
        'javascript/promise-and-async-await',
        'javascript/syntax-vs-python',
        'javascript/type-assertion-as-vs-pydantic',
        'javascript/spread-operator',
        'javascript/event-emitter',
        'javascript/connection-pool-and-release',
        'javascript/knex-and-read-write-splitting',
      ],
    },
    {
      type: 'category',
      label: 'Kubernetes & Docker',
      items: [
        'kubernetes/k8s-concepts',
        'kubernetes/k8s-ingress-and-service',
        'kubernetes/k8s-workloads',
        'kubernetes/k8s-storage',
        'kubernetes/k8s-cronjob',
        'kubernetes/k8s-observability',
        'kubernetes/k8s-and-aws-glossary',
        'kubernetes/k8s-deployment-tools',
        'kubernetes/docker-tips',
      ],
    },
    {
      type: 'category',
      label: 'Monitoring',
      items: [
        'monitoring/prometheus-glossary',
        'monitoring/glossary-and-data-definitions',
        'monitoring/centralized-monitoring-proposal',
        'monitoring/cost-analysis-centralized-monitoring',
        'monitoring/decision-rejected-signoz',
        'monitoring/prometheus-docker-compose',
      ],
    },
    {
      type: 'category',
      label: 'Database',
      items: [
        'database/alembic',
        'database/sqlalchemy-orm-cheatsheet',
        'database/sqlite-to-postgresql',
        'database/postgresql-notes',
      ],
    },
    {
      type: 'category',
      label: 'Python',
      items: [
        'python/context-manager',
        'python/singleton-pattern',
      ],
    },
    {
      type: 'category',
      label: 'Keycloak',
      items: [
        'keycloak/keycloak-concepts',
      ],
    },
    {
      type: 'category',
      label: 'Linux',
      items: [
        'linux/linux-permissions',
      ],
    },
    {
      type: 'category',
      label: 'FFmpeg',
      items: [
        'ffmpeg/compression',
      ],
    },
    {
      type: 'category',
      label: 'MCP',
      items: [
        'mcp/mcp-problem-record',
      ],
    },
  ],
};

module.exports = sidebars;
