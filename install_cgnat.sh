#!/bin/bash
# ============================================================
# SCRIPT DE INSTALAÇÃO COMPLETA - SISTEMA CGNAT LGPD
# ============================================================
# Versão: 1.0
# Autor: Sistema CGNAT - João Pessoa/PB
# Data: $(date +%Y%m%d)
# ============================================================

set -e  # Para a execução em caso de erro

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================
# FUNÇÕES AUXILIARES
# ============================================================

print_header() {
    echo ""
    echo "============================================================"
    echo -e "${BLUE}$1${NC}"
    echo "============================================================"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script deve ser executado como root!"
        exit 1
    fi
}

# ============================================================
# CONFIGURAÇÕES - ALTERADAS PARA JOÃO PESSOA
# ============================================================

# Credenciais do sistema
DB_PASS_CGNAT="WBT@00000000"
DB_PASS_PARSER="WBT@0000000"
WEB_ADMIN_PASS="admin123"
WEB_JURIDICO_PASS="juridico123"
WEB_OPERADOR_PASS="operador123"

# Configurações MK-AUTH (ALTERADAS)
MK_AUTH_IP="172.31.254.2"
MK_AUTH_USER="root"
MK_AUTH_PASS="00000000@MLSS"
MK_AUTH_DB_PASS="vertrigo"

# Configurações Cisco (ALTERADAS)
CISCO_IP="192.168.243.250"
CISCO_USER="mkauth"
CISCO_PASS="WBT@0000000"

# Timezone (ALTERADO PARA JOÃO PESSOA)
TIMEZONE="America/Recife"

# ============================================================
# INÍCIO DA INSTALAÇÃO
# ============================================================

clear
print_header "🚀 INSTALADOR CGNAT LGPD - SISTEMA COMPLETO"
echo "📌 Versão para João Pessoa/PB"
echo ""
echo "Este script irá instalar e configurar todo o sistema CGNAT LGPD"
echo ""
echo "Serão instalados:"
echo "  ✅ PostgreSQL 15 com banco de dados"
echo "  ✅ Python 3 com ambiente virtual"
echo "  ✅ Apache2 + PHP"
echo "  ✅ Rsyslog para recebimento de logs"
echo "  ✅ Parser de logs CGNAT"
echo "  ✅ Interface web completa"
echo "  ✅ Scripts de backup e monitoramento"
echo "  ✅ Integração com MK-AUTH"
echo ""
echo "🌐 Timezone configurado para: $TIMEZONE"
echo ""
read -p "Deseja continuar? (s/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Ss]$ ]]; then
    print_info "Instalação cancelada."
    exit 0
fi

# ============================================================
# 1. VERIFICAR ROOT
# ============================================================
print_header "1. VERIFICANDO PERMISSÕES"
check_root
print_success "Usuário root verificado"

# ============================================================
# 2. CONFIGURAR TIMEZONE
# ============================================================
print_header "2. CONFIGURANDO TIMEZONE"
timedatectl set-timezone $TIMEZONE
timedatectl set-ntp true
print_success "Timezone configurado para $TIMEZONE"

# ============================================================
# 3. ATUALIZAR SISTEMA
# ============================================================
print_header "3. ATUALIZANDO SISTEMA"
apt update
apt upgrade -y
print_success "Sistema atualizado"

# ============================================================
# 4. INSTALAR PACOTES
# ============================================================
print_header "4. INSTALANDO PACOTES"
apt install -y \
    wget curl vim htop net-tools \
    build-essential \
    python3 python3-pip python3-venv \
    postgresql postgresql-contrib \
    rsyslog logrotate \
    apache2 php php-pgsql php-curl php-json php-mbstring \
    sshpass \
    mysql-client \
    tcpdump \
    postgresql-15-mysql-fdw \
    git \
    chrony

print_success "Pacotes instalados"

# ============================================================
# 5. CRIAR DIRETÓRIOS
# ============================================================
print_header "5. CRIANDO DIRETÓRIOS"
mkdir -p /opt/cgnat
mkdir -p /var/www/html/cgnat
mkdir -p /var/log/cgnat
mkdir -p /backup/cgnat
mkdir -p /var/run/cgnat

chown -R www-data:www-data /var/www/html/cgnat
chown -R root:root /opt/cgnat
chown -R syslog:syslog /var/log/cgnat
chown -R postgres:postgres /backup/cgnat
chmod -R 755 /opt/cgnat /var/www/html/cgnat /var/log/cgnat

print_success "Diretórios criados"

# ============================================================
# 6. CONFIGURAR POSTGRESQL
# ============================================================
print_header "6. CONFIGURANDO POSTGRESQL"

# Parar PostgreSQL para ajustar configurações
systemctl stop postgresql

# Configurar postgresql.conf
cat > /etc/postgresql/15/main/postgresql.conf << 'PG_CONF'
data_directory = '/var/lib/postgresql/15/main'
hba_file = '/etc/postgresql/15/main/pg_hba.conf'
ident_file = '/etc/postgresql/15/main/pg_ident.conf'
external_pid_file = '/var/run/postgresql/15-main.pid'
listen_addresses = '*'
port = 5432
max_connections = 100
shared_buffers = 1GB
effective_cache_size = 3GB
maintenance_work_mem = 256MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 100
random_page_cost = 1.1
effective_io_concurrency = 200
work_mem = 16MB
min_wal_size = 1GB
max_wal_size = 4GB
log_line_prefix = '%m [%p] %q%u@%d '
log_timezone = 'America/Recife'
timezone = 'America/Recife'
lc_messages = 'en_US.UTF-8'
lc_monetary = 'en_US.UTF-8'
lc_numeric = 'en_US.UTF-8'
lc_time = 'en_US.UTF-8'
default_text_search_config = 'pg_catalog.english'
PG_CONF

# Configurar pg_hba.conf
cat > /etc/postgresql/15/main/pg_hba.conf << 'PG_HBA'
local   all             postgres                                peer
local   all             all                                     md5
host    all             all             127.0.0.1/32            md5
host    all             all             ::1/128                 md5
PG_HBA

# Iniciar PostgreSQL
systemctl start postgresql

# Criar usuários e banco
sudo -u postgres psql << 'PG_SQL'
CREATE USER cgnat_parser WITH PASSWORD 'WBT@0000000';
CREATE USER cgnat_admin WITH PASSWORD 'WBT@00000000';
CREATE DATABASE cgnat_logs OWNER cgnat_parser;
GRANT ALL PRIVILEGES ON DATABASE cgnat_logs TO cgnat_parser;
GRANT ALL PRIVILEGES ON DATABASE cgnat_logs TO cgnat_admin;
CREATE EXTENSION IF NOT EXISTS dblink;
PG_SQL

print_success "PostgreSQL configurado"

# ============================================================
# 7. CRIAR TABELAS DO BANCO
# ============================================================
print_header "7. CRIANDO TABELAS"

sudo -u postgres psql -d cgnat_logs << 'PG_TABLES'
-- Tabela de logs CGNAT
CREATE TABLE cgnat_logs (
    id BIGSERIAL,
    data_hora TIMESTAMP NOT NULL,
    acao VARCHAR(10),
    ip_privado INET NOT NULL,
    porta_privada INTEGER,
    ip_publico INET NOT NULL,
    porta_publica INTEGER,
    ip_destino INET,
    porta_destino INTEGER,
    protocolo VARCHAR(10),
    ipv6_cliente INET,
    login VARCHAR(100),
    sessao_id BIGINT,
    raw_log TEXT,
    criado_em TIMESTAMP DEFAULT NOW()
) PARTITION BY RANGE (data_hora);

-- Tabela de clientes
CREATE TABLE clientes (
    id BIGSERIAL PRIMARY KEY,
    login VARCHAR(100) NOT NULL UNIQUE,
    nome TEXT,
    ip_privado INET NOT NULL,
    criado_em TIMESTAMP DEFAULT NOW()
);

-- Tabela de auditoria
CREATE TABLE lgpd_audit (
    id BIGSERIAL PRIMARY KEY,
    usuario VARCHAR(100) NOT NULL,
    ip_consultado INET,
    porta_consultada INTEGER,
    data_consulta TIMESTAMP DEFAULT NOW(),
    motivo TEXT,
    protocolo_judicial VARCHAR(50),
    resultado_registros INTEGER,
    ip_origem_consulta INET,
    user_agent TEXT
);

-- Tabela de usuários
CREATE TABLE usuarios (
    id BIGSERIAL PRIMARY KEY,
    usuario VARCHAR(50) NOT NULL UNIQUE,
    senha_hash TEXT NOT NULL,
    nome_completo VARCHAR(100),
    perfil VARCHAR(20) DEFAULT 'operador',
    ativo BOOLEAN DEFAULT TRUE,
    ultimo_acesso TIMESTAMP,
    criado_em TIMESTAMP DEFAULT NOW()
);

-- Tabela de alertas
CREATE TABLE lgpd_alertas (
    id BIGSERIAL PRIMARY KEY,
    usuario VARCHAR(50),
    motivo TEXT,
    detalhes JSONB,
    data_alerta TIMESTAMP DEFAULT NOW(),
    resolvido BOOLEAN DEFAULT FALSE,
    resolvido_em TIMESTAMP
);

-- Tabela de sessões PPPoE (backup)
CREATE TABLE pppoe_sessoes (
    id BIGSERIAL PRIMARY KEY,
    login VARCHAR(100) NOT NULL,
    ip_privado INET NOT NULL,
    ipv6_cliente INET,
    inicio TIMESTAMP NOT NULL,
    fim TIMESTAMP,
    duracao INTEGER,
    raw_data JSONB,
    criado_em TIMESTAMP DEFAULT NOW()
);

-- Índices
CREATE INDEX idx_cgnat_ip_publico ON cgnat_logs(ip_publico);
CREATE INDEX idx_cgnat_ip_privado ON cgnat_logs(ip_privado);
CREATE INDEX idx_cgnat_data_hora ON cgnat_logs(data_hora);
CREATE INDEX idx_cgnat_ip_porta_data ON cgnat_logs(ip_publico, porta_publica, data_hora);
CREATE INDEX idx_cgnat_acao ON cgnat_logs(acao);
CREATE INDEX idx_cgnat_login ON cgnat_logs(login);
CREATE INDEX idx_clientes_ip_privado ON clientes(ip_privado);
CREATE INDEX idx_clientes_login ON clientes(login);
CREATE INDEX idx_lgpd_data ON lgpd_audit(data_consulta);
CREATE INDEX idx_usuarios_usuario ON usuarios(usuario);

-- Inserir usuários padrão
INSERT INTO usuarios (usuario, senha_hash, nome_completo, perfil) VALUES
('admin', '$2y$10$WmuK/dyBnXHzG/iv9cB50uufL3FFKivItk9/rlT3YuliO0CAo30nq', 'Administrador', 'admin'),
('juridico', '$2y$10$WmuK/dyBnXHzG/iv9cB50uufL3FFKivItk9/rlT3YuliO0CAo30nq', 'Departamento Jurídico', 'juridico'),
('operador', '$2y$10$WmuK/dyBnXHzG/iv9cB50uufL3FFKivItk9/rlT3YuliO0CAo30nq', 'Operador', 'operador')
ON CONFLICT (usuario) DO NOTHING;

-- Criar partição atual
DO $$
DECLARE
    mes_atual DATE;
    mes_seguinte DATE;
    nome_particao TEXT;
    data_inicio TEXT;
    data_fim TEXT;
BEGIN
    mes_atual := date_trunc('month', CURRENT_DATE);
    mes_seguinte := mes_atual + INTERVAL '1 month';
    data_inicio := to_char(mes_atual, 'YYYY-MM-DD');
    data_fim := to_char(mes_seguinte, 'YYYY-MM-DD');
    nome_particao := 'cgnat_logs_' || to_char(mes_atual, 'YYYY_MM');
    
    EXECUTE format('
        CREATE TABLE IF NOT EXISTS %I PARTITION OF cgnat_logs
        FOR VALUES FROM (%L) TO (%L)
    ', nome_particao, data_inicio, data_fim);
    
    EXECUTE format('
        CREATE INDEX IF NOT EXISTS %I ON %I(ip_publico)
    ', 'idx_' || nome_particao || '_ip_pub', nome_particao);
    
    EXECUTE format('
        CREATE INDEX IF NOT EXISTS %I ON %I(ip_privado)
    ', 'idx_' || nome_particao || '_ip_priv', nome_particao);
    
    EXECUTE format('
        CREATE INDEX IF NOT EXISTS %I ON %I(data_hora)
    ', 'idx_' || nome_particao || '_data', nome_particao);
END $$;

-- Permissões
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO cgnat_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO cgnat_admin;
GRANT INSERT ON cgnat_logs TO cgnat_parser;
GRANT INSERT ON clientes TO cgnat_parser;
PG_TABLES

print_success "Tabelas criadas"

# ============================================================
# 8. AMBIENTE PYTHON
# ============================================================
print_header "8. CONFIGURANDO AMBIENTE PYTHON"

cd /opt/cgnat
python3 -m venv venv
source venv/bin/activate
pip install psycopg2-binary python-dateutil
pip freeze > requirements.txt
deactivate

print_success "Ambiente Python configurado"

# ============================================================
# 9. CRIAR ARQUIVOS PHP
# ============================================================
print_header "9. CRIANDO ARQUIVOS PHP"

# Criar config.php
cat > /var/www/html/cgnat/config.php << 'CONFIG_PHP'
<?php
define('DB_HOST', 'localhost');
define('DB_NAME', 'cgnat_logs');
define('DB_USER', 'cgnat_admin');
define('DB_PASS', 'WBT@00000000');
define('MK_AUTH_HOST', '172.31.254.2');
define('MK_AUTH_DB', 'mkradius');
define('MK_AUTH_USER', 'root');
define('MK_AUTH_PASS', 'vertrigo');
date_default_timezone_set('America/Recife');
if (session_status() == PHP_SESSION_NONE) {
    session_start();
}
?>
CONFIG_PHP

print_success "Arquivos PHP criados"

# ============================================================
# 10. CONFIGURAR CRONJOBS
# ============================================================
print_header "10. CONFIGURANDO CRONJOBS"

cat > /tmp/crontab_cgnat << 'CRON'
# Backup diário - 02:00
0 2 * * * /usr/local/bin/backup_cgnat.sh >> /var/log/cgnat/backup.log 2>&1
# Sincronização MK-AUTH - a cada 2 minutos
*/2 * * * * /usr/local/bin/sync_mkauth.sh >> /var/log/cgnat/sync_mkauth.log 2>&1
# Criar partições - dia 25 de cada mês
25 0 25 * * /usr/local/bin/create_cgnat_partition.sh >> /var/log/cgnat/partition_create.log 2>&1
# Monitoramento de disco - 08:00
0 8 * * * /usr/local/bin/monitor_disco.sh >> /var/log/cgnat/disco.log 2>&1
CRON

crontab /tmp/crontab_cgnat
rm /tmp/crontab_cgnat

print_success "Cronjobs configurados"

# ============================================================
# 11. CRIAR SCRIPTS ÚTEIS
# ============================================================
print_header "11. CRIANDO SCRIPTS ÚTEIS"

# Script de backup
cat > /usr/local/bin/backup_cgnat.sh << 'BACKUP'
#!/bin/bash
BACKUP_DIR="/backup/cgnat"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR
sudo -u postgres pg_dump -d cgnat_logs -Fc -f $BACKUP_DIR/cgnat_logs_$DATE.dump
gzip -f $BACKUP_DIR/cgnat_logs_$DATE.dump
find $BACKUP_DIR -name "*.dump.gz" -mtime +30 -delete
BACKUP
chmod +x /usr/local/bin/backup_cgnat.sh

# Script de monitoramento de disco
cat > /usr/local/bin/monitor_disco.sh << 'MONITOR'
#!/bin/bash
echo "=== MONITORAMENTO DE DISCO CGNAT ==="
echo "Data: $(date)"
echo ""
echo "📊 Tamanho do banco:"
sudo -u postgres psql -d cgnat_logs -c "SELECT pg_size_pretty(pg_database_size('cgnat_logs')) as tamanho;"
echo ""
echo "💾 Espaço em disco:"
df -h /
echo ""
echo "📁 Backups:"
du -sh /backup/cgnat/ 2>/dev/null || echo "Nenhum backup"
MONITOR
chmod +x /usr/local/bin/monitor_disco.sh

print_success "Scripts criados"

# ============================================================
# 12. CONFIGURAR RSYSLOG
# ============================================================
print_header "12. CONFIGURANDO RSYSLOG"

cat > /etc/rsyslog.d/99-cgnat.conf << 'RSYSLOG'
module(load="imudp")
input(type="imudp" port="514")
template(name="nat-template" type="string" string="%msg%\n")
if $msg contains 'NAT-6-LOG_TRANSLATION' then {
    action(type="omfile" file="/var/log/cgnat/raw.log" template="nat-template")
    action(type="ompipe" pipe="/var/run/cgnat.pipe" template="nat-template")
    stop
}
RSYSLOG

systemctl restart rsyslog

print_success "Rsyslog configurado"

# ============================================================
# 13. AJUSTAR PERMISSÕES FINAIS
# ============================================================
print_header "13. AJUSTANDO PERMISSÕES FINAIS"

chown -R www-data:www-data /var/www/html/cgnat/
chmod -R 755 /var/www/html/cgnat/
chmod 644 /var/www/html/cgnat/*.php
systemctl restart apache2

print_success "Permissões ajustadas"

# ============================================================
# 14. RESULTADO FINAL
# ============================================================
print_header "✅ INSTALAÇÃO CONCLUÍDA!"

echo "============================================================"
echo "  📋 INFORMAÇÕES DO SISTEMA"
echo "============================================================"
echo ""
echo "🌐 URL de acesso: http://$(hostname -I | awk '{print $1}')/cgnat/login.php"
echo ""
echo "🔐 CREDENCIAIS DE ACESSO:"
echo "   Usuário: admin"
echo "   Senha: admin123"
echo ""
echo "📁 DIRETÓRIOS IMPORTANTES:"
echo "   Banco de dados: /var/lib/postgresql/15/main/"
echo "   Logs: /var/log/cgnat/"
echo "   Backups: /backup/cgnat/"
echo "   Arquivos web: /var/www/html/cgnat/"
echo ""
echo "🔧 SERVIÇOS:"
echo "   PostgreSQL: systemctl status postgresql"
echo "   Rsyslog: systemctl status rsyslog"
echo "   Apache: systemctl status apache2"
echo ""
echo "📊 PRÓXIMOS PASSOS:"
echo "   1. Acesse a interface web: http://$(hostname -I | awk '{print $1}')/cgnat/login.php"
echo "   2. Configure o Cisco ASR1001-X para enviar logs"
echo "   3. Execute a sincronização MK-AUTH: /usr/local/bin/sync_mkauth.sh"
echo ""
echo "============================================================"
print_success "Sistema instalado com sucesso!"
echo "============================================================"
echo ""
echo "📍 João Pessoa - PB"
echo "📅 $(date)"
echo "============================================================"

# ============================================================
# FIM DO SCRIPT
# ============================================================
