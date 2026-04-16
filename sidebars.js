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
      label: 'Kubernetes',
      items: [
        'kubernetes/k8s-concepts',
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
