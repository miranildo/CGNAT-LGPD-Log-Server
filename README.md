# 🚀 CGNAT LGPD - Instalador Automático

**Sistema completo de consulta CGNAT para atendimento à LGPD**

> Versão otimizada WEBLINE TELECOM para João Pessoa - PB

## 📋 O que é?

Sistema para coletar, armazenar e consultar logs de NAT do Cisco ASR1001-X, com identificação de clientes via integração com MK-AUTH, totalmente em conformidade com a LGPD.

## ⚡ Instalação Rápida

```bash
bash <(curl -s https://raw.githubusercontent.com/miranildo/CGNAT-LGPD-Log-Server/main/install_lgpd-logs.sh)
```

## ⚡ Instalação Local

```bash
wget -O install_cgnat.sh https://raw.githubusercontent.com/miranildo/CGNAT-LGPD-Log-Server/main/install_cgnat.sh
chmod +x install_cgnat.sh
```

## ⚡ Apos a instalação antes de executar o instalador ajuste seu parâmetros de acordo com sua rede
```bash

# ============================================================
# CONFIGURAÇÕES
# ============================================================

DB_PASS_CGNAT="ABC@00000000"
DB_PASS_PARSER="ABC@0000000"
MK_AUTH_IP="172.31.254.2"
MK_AUTH_USER="root"
MK_AUTH_PASS="00000000@Abcd"
MK_AUTH_DB_PASS="vertrigo"
CISCO_IP="192.168.100.1"
CISCO_USER="mkauth"
CISCO_PASS="ABC@0000000"
TIMEZONE="America/Recife"

```
