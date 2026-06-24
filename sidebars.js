/** @type {import('@docusaurus/plugin-content-docs').SidebarsConfig} */
const sidebars = {
  tutorialSidebar: [
    'intro',
    {
      type: 'category',
      label: 'AWS',
      items: [
        'aws/aws-glossary-nav',
        'aws/aws-services-glossary',
        'aws/self-managed-vs-fully-managed',
        'aws/nat-gateway-vs-transit-gateway',
        'aws/acm-guide',
        'aws/irsa-guide',
        'aws/iam-guide',
        'aws/ecr-nav',
        'aws/ec2-guide',
        'aws/ebs-guide',
        'aws/rds-guide',
        'aws/s3-guide',
        'aws/alb-guide',
        'aws/route53-guide',
        'aws/eks-guide',
        'aws/eks-node-group-subnet-migration',
        'aws/eks-node-group-taint-affinity',
        'aws/k8s-lb-binding-flow',
        'aws/cli-credentials-guide',
        'aws/dynamodb-guide',
        'aws/dynamodb-no-connection-pool',
        'aws/service-token-dynamodb',
        'aws/sqs-client-and-md5',
        'aws/sqs-polling-and-vs-rabbitmq',
      ],
    },
    {
      type: 'category',
      label: 'DevOps',
      items: [
        'devops/terraform/glossary',
        'devops/terraform/import-vs-git-push-pull',
      
        'devops/terraform/outputs-and-remote-state',
      ],
    },
    {
      type: 'category',
      label: 'Design Pattern',
      items: [
        'design-pattern/monorepo',
        'design-pattern/singleton-pattern',
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
        'kubernetes/k8s-nav',
        'kubernetes/k8s-concepts',
        'kubernetes/k8s-ingress-and-service',
        'kubernetes/k8s-workloads',
        'kubernetes/k8s-storage',
        'kubernetes/k8s-cronjob',
        'kubernetes/k8s-observability',
        'kubernetes/k8s-operator-pattern',
        'kubernetes/k8s-glossary',
        'kubernetes/k8s-deployment-tools',
        'docker/docker-tips',
      ],
    },
    {
      type: 'category',
      label: 'Monitoring',
      items: [
        'monitoring/prometheus-glossary',
        'monitoring/vm-glossary',
        'monitoring/1-monitoring-tech-selection',
        'monitoring/2-thanos-vs-victoriametrics',
        'monitoring/3-thanos-architecture',
        'monitoring/4-victoriametrics-architecture',
        'monitoring/5-multi-region-monitoring-architecture',
        'monitoring/6-vm-self-monitoring',
        'monitoring/7-alerting-ha-design',
        'monitoring/8-vm-operator-vs-helm',
        'monitoring/prometheus-ha-limitations',
        'monitoring/thanos-self-monitoring',
        'monitoring/alert-driven-dashboard-philosophy',
        'monitoring/dashboard-design-principles',
        'monitoring/grafana-microsoft-aad-cannot-rotate-token',
        'monitoring/yace-deployment-guide',
        'monitoring/Google SRE - Critical User Journey',
        'monitoring/prometheus-default-metrics-reference',
      
        'monitoring/prometheus-python-instrumentation',
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
      label: 'MCP',
      items: [
        'mcp/mcp-problem-record',
      ],
    },
  ],
};

module.exports = sidebars;
