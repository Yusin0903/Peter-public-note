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

> **Python analogy**: Like manually `pip install`-ing every package, managing virtualenvs yourself, writing your own backup scripts — all infrastructure is your responsibility.
>
> ```python
> import subprocess
>
> subprocess.run(["apt", "install", "mysql-server"])   # install
> subprocess.run(["mysqldump", "-u", "root", "mydb"])  # backup (you write this)
> subprocess.run(["systemctl", "restart", "mysql"])    # crashed? restart yourself
> ```

---

## Fully Managed (DynamoDB)

AWS handles it — you just use it:

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

> **Python analogy**: Like using `boto3` directly — you only write business logic, infrastructure is completely AWS's concern.
>
> ```python
> import boto3
>
> # Fully managed: you only write this, everything underneath is AWS's problem
> dynamodb = boto3.resource("dynamodb", region_name="us-east-1")
> table = dynamodb.Table("my-table")
>
> table.put_item(Item={"id": "123", "value": "hello"})
> response = table.get_item(Key={"id": "123"})
> # Backups? Scaling? HA? → AWS handles it automatically
> ```

---

## One-Line Summary

| | Self-managed (EC2 + MySQL) | Fully Managed (DynamoDB) |
|---|---|---|
| Analogy | Buy ingredients, cook yourself, wash the dishes | Order at a restaurant, kitchen is not your concern |
| Python comparison | Build server + write all tooling scripts | Just `import boto3` and use it |
| Flexibility | High (full control) | Low (AWS owns the internals) |
| Ops burden | High | Near zero |
