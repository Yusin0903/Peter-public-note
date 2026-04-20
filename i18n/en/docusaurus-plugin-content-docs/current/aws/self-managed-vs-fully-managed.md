---
sidebar_position: 1
---

# Self-managed vs Fully Managed

## Self-managed (MySQL on EC2)

You handle everything yourself:

```
You are responsible for:
├── Launching EC2 and installing MySQL
├── Configuring CPU / Memory
├── Expanding disk when nearly full
├── Regular backups
├── Version upgrades / security patches
├── Primary-replica replication (high availability)
├── Monitoring and alerting
└── Fixing issues when things break
```

## Fully Managed (DynamoDB)

AWS handles it for you — you just use it:

```
AWS is responsible for:
├── Hardware, OS, database engine
├── Auto scaling
├── Automatic backups
├── Automatic cross-AZ replication (high availability)
├── Security patches
└── Monitoring

You only need to:
├── Create tables
├── Read and write data
└── Pay the bill (pay-per-use)
```

## One-liner

- Self-managed = you buy ingredients and cook yourself
- Fully managed = you order at a restaurant, the kitchen is not your concern
