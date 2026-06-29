#!/bin/bash
# ============================================================
# SCRIPT DE INSTALAÇÃO - SISTEMA CGNAT LGPD VERSÃO 1.0
# ============================================================
# Versão: 1.0 - Debian 12 e 13 x64
# Autor: WEBLINE TELECOM - Sistema CGNAT - João Pessoa/PB
# Router: Cisco ASR-1001X
# ============================================================

set -e

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo ""
    echo "============================================================"
    echo -e "${BLUE}$1${NC}"
    echo "============================================================"
    echo ""
}

print_success() { echo -e "${GREEN}✅ $1${NC}"; }
print_error() { echo -e "${RED}❌ $1${NC}"; }
print_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
print_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "Este script deve ser executado como root!"
        exit 1
    fi
}

# ============================================================
# CONFIGURAÇÕES
# ============================================================
DB_PASS_CGNAT="Wbt@07717125"
DB_PASS_PARSER="Wbt@07717125"
MK_AUTH_IP="172.31.255.2"
MK_AUTH_USER="root"
MK_AUTH_PASS="25077171@Mlss"
MK_AUTH_DB_PASS="vertrigo"
MK_AUTH_DB_TABLE="mkradius"
CISCO_IP="190.196.243.250"
CISCO_USER="admin"
CISCO_PASS="Wbt077171"
TIMEZONE="America/Recife"
TEL_TOKEN="8770565011:AAFoGTqjtVb06WFyCvBG-jF_9DDuNSapGik"
TEL_CHAT_ID="-1003792217019"
TEL_ENVIO="SIM"
MAX_TENTATIVAS="3"

# ============================================================
# INÍCIO
# ============================================================

clear
print_header "🚀 INSTALADOR LGPD CGNAT LOGS"
echo "📌 Versão 1.0"
echo ""
echo "Serão instalados:"
echo "  ✅ PostgreSQL 15 com banco de dados"
echo "  ✅ Python 3 com ambiente virtual"
echo "  ✅ Apache2 + PHP"
echo "  ✅ Rsyslog para recebimento de logs"
echo "  ✅ Parser de logs CGNAT (com permissões corrigidas)"
echo "  ✅ Interface web completa (TODAS AS PÁGINAS)"
echo "  ✅ Scripts de backup e monitoramento"
echo "  ✅ Integração com MK-AUTH (usando sis_cliente e sis_adicional)"
echo "  ✅ Sincronização IPv6 do Cisco ASR"
echo "  ✅ Busca IPv6 independente (não depende de CGNAT)"
echo "  ✅ Monitoramento automático do /dev/shm"
echo ""
echo "🌐 Timezone configurado para: $TIMEZONE"
echo ""
read -p "Deseja continuar? (S/N): " -n 1 -r
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
# 2.5. CONFIGURAR /dev/shm (16GB)
# ============================================================
print_header "2.5. CONFIGURANDO /dev/shm (16GB)"

# Verificar se /dev/shm está montado
if mount | grep -q "/dev/shm"; then
    print_info "/dev/shm já está montado"
else
    print_warning "/dev/shm não montado. Montando..."
    mount -t tmpfs -o size=16G tmpfs /dev/shm
fi

# Aumentar para 16GB
mount -o remount,size=16G /dev/shm 2>/dev/null || true

# Tornar permanente no fstab
if ! grep -q "tmpfs /dev/shm" /etc/fstab; then
    echo "tmpfs /dev/shm tmpfs defaults,size=16G 0 0" >> /etc/fstab
    print_info "Entrada adicionada no /etc/fstab"
fi

# Limpar arquivos órfãos
rm -rf /dev/shm/PostgreSQL.* 2>/dev/null
rm -rf /dev/shm/sem.* 2>/dev/null
rm -rf /dev/shm/.s.PGSQL.* 2>/dev/null
rm -rf /dev/shm/cgnat_logs 2>/dev/null

print_success "/dev/shm configurado com 16GB"
df -h /dev/shm

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

# Detectar versão do Debian
if command -v lsb_release &> /dev/null; then
    DEBIAN_VERSION=$(lsb_release -rs)
    DEBIAN_CODENAME=$(lsb_release -cs)
else
    if grep -q "bookworm" /etc/os-release 2>/dev/null; then
        DEBIAN_VERSION="12"
        DEBIAN_CODENAME="bookworm"
    elif grep -q "trixie" /etc/os-release 2>/dev/null; then
        DEBIAN_VERSION="13"
        DEBIAN_CODENAME="trixie"
    else
        DEBIAN_VERSION="12"
        DEBIAN_CODENAME="bookworm"
    fi
fi

print_info "Detectado Debian ${DEBIAN_VERSION} (${DEBIAN_CODENAME})"

# Instalar pacotes base
print_info "Instalando pacotes base..."
apt update
apt install -y \
    sudo \
    wget curl vim htop net-tools \
    build-essential \
    gnupg \
    python3 python3-pip python3-venv \
    postgresql postgresql-contrib \
    rsyslog logrotate \
    apache2 \
    sshpass \
    default-mysql-client \
    tcpdump \
    git \
    chrony \
    iotop \
    smartmontools \
    sysstat \
    php \
    php-pgsql \
    php-curl \
    php-mbstring

print_success "Pacotes base instalados"

# Instalar mysql_fdw
print_info "Instalando postgresql-15-mysql-fdw..."
if ! dpkg -l 2>/dev/null | grep -q "postgresql-15-mysql-fdw"; then
    case "${DEBIAN_VERSION}" in
        12|bookworm)
            apt install -y postgresql-15-mysql-fdw
            ;;
        *)
            mkdir -p /usr/share/keyrings
            curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg 2>/dev/null || wget -q -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
            echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt ${DEBIAN_CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list
            apt update
            apt install -y postgresql-15-mysql-fdw
            ;;
    esac
fi

print_success "Pacotes instalados"

# ============================================================
# 4.5. FIXAR VERSÃO DO POSTGRESQL (DEFINITIVO)
# ============================================================
print_header "4.5. FIXANDO VERSÃO DO POSTGRESQL"

# REMOVER METAPACOTE
print_info "Removendo metapacote 'postgresql'..."
if dpkg -l 2>/dev/null | grep -q "^ii  postgresql "; then
    DEBIAN_FRONTEND=noninteractive dpkg -r --force-depends postgresql 2>/dev/null || true
fi

# REMOVER 17 E 18
print_info "Removendo PostgreSQL 17/18..."
for VER in 17 18; do
    if pg_lsclusters 2>/dev/null | grep -q "${VER}.*online"; then
        print_info "Parando cluster PostgreSQL ${VER}..."
        systemctl stop postgresql@${VER}-main 2>/dev/null
        pg_dropcluster ${VER} main --stop 2>/dev/null
    fi
done

for VER in 17 18; do
    if dpkg -l 2>/dev/null | grep -q "postgresql-${VER}"; then
        print_info "Removendo PostgreSQL ${VER}..."
        DEBIAN_FRONTEND=noninteractive dpkg --remove --force-remove-reinstreq postgresql-${VER} 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive dpkg --remove --force-remove-reinstreq postgresql-client-${VER} 2>/dev/null || true
    fi
done

# REMOVER RESÍDUOS
print_info "Removendo resíduos do PostgreSQL 17/18..."
for VER in 17 18; do
    if dpkg -l 2>/dev/null | grep -q "rc  postgresql-${VER}"; then
        print_info "Removendo resíduos do PostgreSQL ${VER}..."
        dpkg --purge postgresql-${VER} 2>/dev/null || true
        dpkg --purge postgresql-client-${VER} 2>/dev/null || true
    fi
done

# REMOVER METAPACOTE RESIDUAL
print_info "Removendo metapacote residual..."
if dpkg -l 2>/dev/null | grep -q "rc  postgresql "; then
    dpkg --purge postgresql 2>/dev/null || true
fi

# CORRIGIR PACOTES
print_info "Corrigindo pacotes quebrados..."
apt --fix-broken install -y 2>/dev/null || true
apt autoremove -y 2>/dev/null || true
apt autoclean -y 2>/dev/null || true

# BLOQUEAR 16/17/18
print_info "Bloqueando PostgreSQL 16, 17 e 18..."
cat > /etc/apt/preferences.d/postgresql-hold << 'EOF'
Package: postgresql-16*
Pin: version *
Pin-Priority: -1

Package: postgresql-17*
Pin: version *
Pin-Priority: -1

Package: postgresql-18*
Pin: version *
Pin-Priority: -1

Package: postgresql-client-16*
Pin: version *
Pin-Priority: -1

Package: postgresql-client-17*
Pin: version *
Pin-Priority: -1

Package: postgresql-client-18*
Pin: version *
Pin-Priority: -1

Package: postgresql
Pin: version *
Pin-Priority: -1
EOF

# FIXAR POSTGRESQL 15
print_info "Fixando PostgreSQL 15..."
apt-mark hold postgresql-15 postgresql-client-15 2>/dev/null || true

if apt-cache show postgresql-contrib-15 2>/dev/null | grep -q "Package: postgresql-contrib-15"; then
    apt-mark hold postgresql-contrib-15 2>/dev/null || true
else
    print_info "postgresql-contrib-15 não disponível - ignorando hold"
fi

print_success "Versão do PostgreSQL fixada (15) e PostgreSQL 17/18 removidos/bloqueados"

# VERIFICAR PORTA 5432
print_info "Verificando porta 5432..."
if ss -tlnp 2>/dev/null | grep -q ":5432"; then
    print_warning "⚠️ Porta 5432 ocupada! Liberando..."
    fuser -k 5432/tcp 2>/dev/null
    sleep 2
    if ss -tlnp 2>/dev/null | grep -q ":5432"; then
        print_error "❌ Não foi possível liberar a porta 5432!"
    else
        print_success "✅ Porta 5432 liberada com sucesso!"
    fi
else
    print_success "✅ Porta 5432 disponível!"
fi

# CRIAR CLUSTER 15 SE NÃO EXISTIR
if ! pg_lsclusters 2>/dev/null | grep -q "15.*online"; then
    print_info "Criando cluster PostgreSQL 15..."
    pg_createcluster 15 main --start -u postgres -p 5432
    systemctl start postgresql@15-main
else
    print_success "✅ PostgreSQL 15 já está rodando!"
fi

# VERIFICAÇÃO FINAL
print_info "Verificando instalação final..."
echo ""
echo "📊 Pacotes PostgreSQL instalados:"
dpkg -l 2>/dev/null | grep postgresql | grep -E "postgresql-[0-9]+" || print_info "✅ Apenas PostgreSQL 15 instalado"
echo ""
echo "📊 Clusters PostgreSQL:"
pg_lsclusters
echo ""
echo "📊 Status do PostgreSQL 15:"
systemctl status postgresql@15-main --no-pager | head -5

print_success "✅ PostgreSQL 15 fixado com sucesso!"

# ============================================================
# 5. CRIAR DIRETÓRIOS
# ============================================================
print_header "5. CRIANDO DIRETÓRIOS"

mkdir -p /opt/cgnat
mkdir -p /var/www/html/cgnat
mkdir -p /var/log/cgnat
mkdir -p /backup/cgnat
mkdir -p /var/run/cgnat

chown -R www-data:www-data /var/www/html/cgnat 2>/dev/null || true
chown -R root:root /opt/cgnat 2>/dev/null || true
chown -R root:root /var/log/cgnat 2>/dev/null || true
chown -R postgres:postgres /backup/cgnat 2>/dev/null || true
chmod -R 755 /opt/cgnat /var/www/html/cgnat /var/log/cgnat 2>/dev/null || true

print_success "Diretórios criados"

# ============================================================
# 5.5. VERIFICAR /dev/shm
# ============================================================
print_header "5.5. VERIFICANDO /dev/shm"

# Limpar arquivos órfãos do PostgreSQL
print_info "Limpando arquivos temporários do PostgreSQL..."
rm -rf /dev/shm/PostgreSQL.* 2>/dev/null
rm -rf /dev/shm/sem.* 2>/dev/null
rm -rf /dev/shm/.s.PGSQL.* 2>/dev/null

df -h /dev/shm
print_success "/dev/shm verificado e limpo"

# ============================================================
# 6. CONFIGURAR POSTGRESQL
# ============================================================
print_header "6. CONFIGURANDO POSTGRESQL"

# Parar qualquer instância existente
systemctl stop postgresql 2>/dev/null || true
systemctl stop postgresql@15-main 2>/dev/null || true
systemctl stop postgresql@17-main 2>/dev/null || true

# Remover clusters existentes
pg_dropcluster 15 main --stop 2>/dev/null || true
rm -rf /var/lib/postgresql/15/main 2>/dev/null || true
rm -f /var/run/postgresql/.s.PGSQL.5432 2>/dev/null || true
rm -f /var/run/postgresql/.s.PGSQL.5432.lock 2>/dev/null || true

# Criar novo cluster
pg_createcluster 15 main --start -u postgres -p 5432

# Otimizar configuração do PostgreSQL
CONF_FILE="/etc/postgresql/15/main/postgresql.conf"
if [ -f "$CONF_FILE" ]; then
    # Garantir porta 5432
    sed -i "s/^port =.*/port = 5432/" "$CONF_FILE" 2>/dev/null || echo "port = 5432" >> "$CONF_FILE"
    
    # Otimizações de performance
    echo "" >> "$CONF_FILE"
    echo "# ============================================================" >> "$CONF_FILE"
    echo "# OTIMIZAÇÕES CGNAT" >> "$CONF_FILE"
    echo "# ============================================================" >> "$CONF_FILE"
    echo "shared_buffers = 256MB" >> "$CONF_FILE"
    echo "effective_cache_size = 768MB" >> "$CONF_FILE"
    echo "maintenance_work_mem = 64MB" >> "$CONF_FILE"
    echo "checkpoint_completion_target = 0.9" >> "$CONF_FILE"
    echo "wal_buffers = 16MB" >> "$CONF_FILE"
    echo "default_statistics_target = 100" >> "$CONF_FILE"
    echo "random_page_cost = 1.1" >> "$CONF_FILE"
    echo "effective_io_concurrency = 200" >> "$CONF_FILE"
    echo "work_mem = 4MB" >> "$CONF_FILE"
    echo "min_wal_size = 512MB" >> "$CONF_FILE"
    echo "max_wal_size = 2GB" >> "$CONF_FILE"
    
    # ============================================================
    # AUTOVACUUM OTIMIZADO (PREVINE CORRUPÇÃO)
    # ============================================================
    echo "" >> "$CONF_FILE"
    echo "# ============================================================" >> "$CONF_FILE"
    echo "# AUTOVACUUM OTIMIZADO PARA CGNAT" >> "$CONF_FILE"
    echo "# ============================================================" >> "$CONF_FILE"
    echo "autovacuum = on" >> "$CONF_FILE"
    echo "autovacuum_vacuum_scale_factor = 0.01" >> "$CONF_FILE"
    echo "autovacuum_vacuum_threshold = 1000" >> "$CONF_FILE"
    echo "autovacuum_analyze_scale_factor = 0.005" >> "$CONF_FILE"
    echo "autovacuum_naptime = 30s" >> "$CONF_FILE"
    echo "autovacuum_max_workers = 4" >> "$CONF_FILE"
    echo "autovacuum_freeze_max_age = 500000000" >> "$CONF_FILE"
    echo "autovacuum_multixact_freeze_max_age = 500000000" >> "$CONF_FILE"
    
    # ============================================================
    # PROTEÇÃO CONTRA CORRUPÇÃO
    # ============================================================
    echo "" >> "$CONF_FILE"
    echo "# ============================================================" >> "$CONF_FILE"
    echo "# PROTEÇÃO CONTRA CORRUPÇÃO" >> "$CONF_FILE"
    echo "# ============================================================" >> "$CONF_FILE"
    echo "wal_level = replica" >> "$CONF_FILE"
    echo "fsync = on" >> "$CONF_FILE"
    echo "synchronous_commit = on" >> "$CONF_FILE"
    echo "wal_sync_method = fdatasync" >> "$CONF_FILE"
    echo "full_page_writes = on" >> "$CONF_FILE"
    echo "wal_compression = on" >> "$CONF_FILE"
    echo "wal_log_hints = on" >> "$CONF_FILE"
fi

# Iniciar PostgreSQL
systemctl start postgresql@15-main
systemctl enable postgresql@15-main
sleep 5

# Verificar
if ! systemctl is-active --quiet postgresql@15-main; then
    print_error "Não foi possível iniciar o PostgreSQL"
    pg_lsclusters
    exit 1
fi

print_success "PostgreSQL 15 rodando na porta 5432"

# ============================================================
# 7. CRIAR USUÁRIOS E BANCO
# ============================================================
print_header "7. CRIANDO USUÁRIOS E BANCO"

sudo -u postgres psql -c "CREATE USER cgnat_parser WITH PASSWORD '${DB_PASS_PARSER}';" 2>/dev/null || true
sudo -u postgres psql -c "CREATE USER cgnat_admin WITH PASSWORD '${DB_PASS_CGNAT}';" 2>/dev/null || true
sudo -u postgres psql -c "CREATE DATABASE cgnat_logs OWNER cgnat_parser;" 2>/dev/null || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE cgnat_logs TO cgnat_parser;" 2>/dev/null || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE cgnat_logs TO cgnat_admin;" 2>/dev/null || true
sudo -u postgres psql -d cgnat_logs -c "CREATE EXTENSION IF NOT EXISTS dblink;" 2>/dev/null || true

print_success "Usuários e banco criados"

# ============================================================
# 8. CRIAR TABELAS (COM PERMISSÕES CORRETAS)
# ============================================================
print_header "8. CRIANDO TABELAS"

sudo -u postgres psql -d cgnat_logs << 'EOF'
CREATE TABLE IF NOT EXISTS cgnat_logs (
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

CREATE TABLE IF NOT EXISTS clientes (
    id BIGSERIAL PRIMARY KEY,
    login VARCHAR(100) NOT NULL UNIQUE,
    nome TEXT,
    ip_privado INET NOT NULL,
    ipv6_prefix TEXT,
    ipv6_address TEXT,
    ipv6_atualizado TIMESTAMP,
    ativo BOOLEAN DEFAULT TRUE,
    data_inativacao TIMESTAMP,
    criado_em TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS historico_ipv6 (
    id BIGSERIAL PRIMARY KEY,
    login VARCHAR(100) NOT NULL,
    ipv6_prefix VARCHAR(50) NOT NULL,
    ipv6_address VARCHAR(50),
    data_inicio TIMESTAMP NOT NULL,
    data_fim TIMESTAMP,
    ativo BOOLEAN DEFAULT TRUE,
    criado_em TIMESTAMP DEFAULT NOW(),
    atualizado_em TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lgpd_audit (
    id BIGSERIAL PRIMARY KEY,
    usuario VARCHAR(100) NOT NULL,
    ip_consultado INET,
    porta_consultada INTEGER,
    data_consulta TIMESTAMP DEFAULT NOW(),
    motivo TEXT,
    protocolo_judicial VARCHAR(50),
    ip_privado INET,
    cliente_nome TEXT,
    ipv6_cliente INET,
    log_data_hora TIMESTAMP,
    log_acao VARCHAR(10),
    log_destino TEXT,
    log_protocolo VARCHAR(10),
    resultado_registros INTEGER,
    ip_origem_consulta INET,
    user_agent TEXT
);

CREATE TABLE IF NOT EXISTS usuarios (
    id BIGSERIAL PRIMARY KEY,
    usuario VARCHAR(50) NOT NULL UNIQUE,
    senha_hash TEXT NOT NULL,
    nome_completo VARCHAR(100),
    perfil VARCHAR(20) DEFAULT 'operador',
    ativo BOOLEAN DEFAULT TRUE,
    ultimo_acesso TIMESTAMP,
    criado_em TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS lgpd_alertas (
    id BIGSERIAL PRIMARY KEY,
    usuario VARCHAR(50),
    motivo TEXT,
    detalhes JSONB,
    data_alerta TIMESTAMP DEFAULT NOW(),
    resolvido BOOLEAN DEFAULT FALSE,
    resolvido_em TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pppoe_sessoes (
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

CREATE OR REPLACE VIEW vw_cgnat_logs_count AS
SELECT COUNT(*) as total FROM cgnat_logs;

-- Índices
CREATE INDEX IF NOT EXISTS idx_cgnat_ip_publico ON cgnat_logs(ip_publico);
CREATE INDEX IF NOT EXISTS idx_cgnat_ip_privado ON cgnat_logs(ip_privado);
CREATE INDEX IF NOT EXISTS idx_cgnat_data_hora ON cgnat_logs(data_hora);
CREATE INDEX IF NOT EXISTS idx_cgnat_ip_porta_data ON cgnat_logs(ip_publico, porta_publica, data_hora);
CREATE INDEX IF NOT EXISTS idx_cgnat_acao ON cgnat_logs(acao);
CREATE INDEX IF NOT EXISTS idx_cgnat_login ON cgnat_logs(login);
CREATE INDEX IF NOT EXISTS idx_cgnat_ipv6 ON cgnat_logs(ipv6_cliente);
CREATE INDEX IF NOT EXISTS idx_clientes_ip_privado ON clientes(ip_privado);
CREATE INDEX IF NOT EXISTS idx_clientes_login ON clientes(login);
CREATE INDEX IF NOT EXISTS idx_clientes_ipv6 ON clientes(ipv6_prefix);
CREATE INDEX IF NOT EXISTS idx_historico_ipv6_login ON historico_ipv6(login);
CREATE INDEX IF NOT EXISTS idx_historico_ipv6_prefix ON historico_ipv6(ipv6_prefix);
CREATE INDEX IF NOT EXISTS idx_historico_ipv6_data_inicio ON historico_ipv6(data_inicio);
CREATE INDEX IF NOT EXISTS idx_historico_ipv6_data_fim ON historico_ipv6(data_fim);
CREATE INDEX IF NOT EXISTS idx_historico_ipv6_ativo ON historico_ipv6(ativo);
CREATE INDEX IF NOT EXISTS idx_lgpd_data ON lgpd_audit(data_consulta);
CREATE INDEX IF NOT EXISTS idx_lgpd_ip_publico ON lgpd_audit(ip_consultado);
CREATE INDEX IF NOT EXISTS idx_lgpd_ip_privado ON lgpd_audit(ip_privado);
CREATE INDEX IF NOT EXISTS idx_lgpd_cliente ON lgpd_audit(cliente_nome);
CREATE INDEX IF NOT EXISTS idx_lgpd_ipv6 ON lgpd_audit(ipv6_cliente);
CREATE INDEX IF NOT EXISTS idx_usuarios_usuario ON usuarios(usuario);

-- Usuários padrão
INSERT INTO usuarios (usuario, senha_hash, nome_completo, perfil) VALUES
('admin', '$2y$10$WmuK/dyBnXHzG/iv9cB50uufL3FFKivItk9/rlT3YuliO0CAo30nq', 'Administrador', 'admin'),
('juridico', '$2y$10$WmuK/dyBnXHzG/iv9cB50uufL3FFKivItk9/rlT3YuliO0CAo30nq', 'Departamento Jurídico', 'juridico'),
('operador', '$2y$10$WmuK/dyBnXHzG/iv9cB50uufL3FFKivItk9/rlT3YuliO0CAo30nq', 'Operador', 'operador')
ON CONFLICT (usuario) DO NOTHING;

-- ============================================================
-- PERMISSÕES CORRETAS (COM SELECT + SEQUENCE)
-- ============================================================
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO cgnat_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO cgnat_admin;

-- Parser: INSERT + SELECT
GRANT INSERT ON cgnat_logs TO cgnat_parser;
GRANT INSERT ON clientes TO cgnat_parser;
GRANT INSERT ON pppoe_sessoes TO cgnat_parser;
GRANT INSERT ON historico_ipv6 TO cgnat_parser;

-- CRÍTICO: SELECT para consultar clientes
GRANT SELECT ON clientes TO cgnat_parser;
GRANT SELECT ON pppoe_sessoes TO cgnat_parser;
GRANT SELECT ON historico_ipv6 TO cgnat_parser;
GRANT SELECT ON vw_cgnat_logs_count TO cgnat_parser;

-- ============================================================
-- CORREÇÃO: PERMISSÃO NA SEQUENCE (PARA O ID AUTOMÁTICO)
-- ============================================================
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO cgnat_parser;

GRANT SELECT ON vw_cgnat_logs_count TO cgnat_admin;

-- ============================================================
-- CRIAR PARTIÇÕES
-- ============================================================
DO $$
DECLARE
    mes_atual DATE;
    mes_seguinte DATE;
    nome_particao TEXT;
    data_inicio TEXT;
    data_fim TEXT;
    i INTEGER;
BEGIN
    FOR i IN 0..12 LOOP
        mes_atual := date_trunc('month', CURRENT_DATE + (i || ' months')::INTERVAL);
        mes_seguinte := mes_atual + INTERVAL '1 month';
        data_inicio := to_char(mes_atual, 'YYYY-MM-DD');
        data_fim := to_char(mes_seguinte, 'YYYY-MM-DD');
        nome_particao := 'cgnat_logs_' || to_char(mes_atual, 'YYYY_MM');
        
        IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = nome_particao) THEN
            EXECUTE format('CREATE TABLE %I PARTITION OF cgnat_logs FOR VALUES FROM (%L) TO (%L)', nome_particao, data_inicio, data_fim);
            EXECUTE format('CREATE INDEX %I ON %I(ip_publico)', 'idx_' || nome_particao || '_ip_pub', nome_particao);
            EXECUTE format('CREATE INDEX %I ON %I(ip_privado)', 'idx_' || nome_particao || '_ip_priv', nome_particao);
            EXECUTE format('CREATE INDEX %I ON %I(data_hora)', 'idx_' || nome_particao || '_data', nome_particao);
            RAISE NOTICE 'Partição % criada', nome_particao;
        END IF;
    END LOOP;
END $$;
EOF

print_success "Tabelas criadas com permissões corrigidas (incluindo SEQUENCE)"

# ============================================================
# 9. AMBIENTE PYTHON
# ============================================================
print_header "9. CONFIGURANDO AMBIENTE PYTHON"

cd /opt/cgnat
python3 -m venv venv
source venv/bin/activate
pip install psycopg2-binary python-dateutil
pip freeze > requirements.txt
deactivate

print_success "Ambiente Python configurado"

# ============================================================
# 10. CRIAR O PARSER PYTHON (COM AUTO-RECONEXÃO)
# ============================================================
print_header "10. CRIANDO PARSER PYTHON"

cat > /opt/cgnat/cgnat_parser.py << EOF
#!/usr/bin/env python3
# /opt/cgnat/cgnat_parser.py - VERSÃO COM AUTO-RECONEXÃO

import re
import sys
import psycopg2
import time
from datetime import datetime
import logging
from typing import Dict, Optional, Tuple

logging.basicConfig(
    filename='/var/log/cgnat/parser.log',
    level=logging.WARNING,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

class CGNATParserASR:
    def __init__(self):
        self.conn = None
        self.connect()
        
        self.timestamp_pattern = re.compile(r'(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\.\d{3})')
        self.nat_pattern = re.compile(r'%NAT-6-LOG_TRANSLATION:\s+(.+)')
        self.translation_pattern = re.compile(
            r'(Created|Deleted)\s+Translation\s+(\w+)\s+([\d.]+):(\d+)\s+([\d.]+):(\d+)\s+([\d.]+):(\d+)\s+([\d.]+):(\d+)\s+(\d+)'
        )
        
        self.stats = {'created': 0, 'deleted': 0, 'errors': 0, 'reconnects': 0}
        self.login_cache = {}
        self.cache_hits = 0
        self.cache_misses = 0
        
    def connect(self):
        """Conecta ao banco com retry automático"""
        max_retries = 5
        retry_delay = 5
        
        for attempt in range(max_retries):
            try:
                if self.conn is not None:
                    try:
                        self.conn.close()
                    except:
                        pass
                
                self.conn = psycopg2.connect(
                    host="localhost",
                    database="cgnat_logs",
                    user="cgnat_parser",
                    password="${DB_PASS_PARSER}",
                    connect_timeout=10
                )
                self.conn.autocommit = False
                logging.warning(f"Conectado ao PostgreSQL (tentativa {attempt + 1})")
                return True
            except Exception as e:
                logging.error(f"Erro ao conectar (tentativa {attempt + 1}): {e}")
                if attempt < max_retries - 1:
                    time.sleep(retry_delay)
                else:
                    logging.error("Falha ao conectar após múltiplas tentativas")
                    return False
        return False
    
    def ensure_connection(self):
        """Garante que a conexão está ativa"""
        if self.conn is None:
            logging.warning("Conexão perdida. Reconectando...")
            self.stats['reconnects'] += 1
            return self.connect()
        
        try:
            cursor = self.conn.cursor()
            cursor.execute("SELECT 1")
            cursor.close()
            return True
        except Exception:
            logging.warning("Conexão com PostgreSQL perdida. Reconectando...")
            self.stats['reconnects'] += 1
            return self.connect()
    
    def parse_log_line(self, line: str) -> Optional[Dict]:
        timestamp_match = self.timestamp_pattern.search(line)
        if timestamp_match:
            data_hora = self.parse_cisco_timestamp(timestamp_match.group(1))
        else:
            data_hora = datetime.now()
        
        nat_match = self.nat_pattern.search(line)
        if not nat_match:
            return None
            
        match = self.translation_pattern.search(nat_match.group(1))
        if not match:
            return None
            
        return {
            'acao': match.group(1),
            'protocolo': match.group(2),
            'ip_privado': match.group(3),
            'porta_privada': int(match.group(4)),
            'ip_publico': match.group(5),
            'porta_publica': int(match.group(6)),
            'ip_destino': match.group(7),
            'porta_destino': int(match.group(8)),
            'data_hora': data_hora
        }
    
    def parse_cisco_timestamp(self, timestamp_str: str) -> datetime:
        current_year = datetime.now().year
        parts = timestamp_str.split('.')
        base_time = parts[0]
        try:
            dt = datetime.strptime(f"{current_year} {base_time}", "%Y %b %d %H:%M:%S")
            if dt > datetime.now():
                dt = dt.replace(year=current_year - 1)
            if len(parts) > 1:
                ms = int(parts[1][:3])
                dt = dt.replace(microsecond=ms * 1000)
            return dt
        except Exception:
            return datetime.now()
    
    def get_pppoe_login(self, ip_privado: str, data_hora: datetime) -> Tuple[Optional[str], Optional[int]]:
        if ip_privado in self.login_cache:
            self.cache_hits += 1
            return self.login_cache[ip_privado], None
        
        self.cache_misses += 1
        
        if not self.ensure_connection():
            return None, None
            
        cursor = self.conn.cursor()
        try:
            cursor.execute("""
                SELECT login
                FROM clientes
                WHERE ip_privado = %s::inet
                LIMIT 1
            """, (ip_privado,))
            
            result = cursor.fetchone()
            if result:
                self.login_cache[ip_privado] = result[0]
                return result[0], None
            
            cursor.execute("""
                SELECT login, id
                FROM pppoe_sessoes
                WHERE ip_privado = %s::inet
                AND inicio <= %s
                AND (fim IS NULL OR fim >= %s)
                ORDER BY inicio DESC
                LIMIT 1
            """, (ip_privado, data_hora, data_hora))
            
            result = cursor.fetchone()
            if result:
                self.login_cache[ip_privado] = result[0]
                return result[0], result[1]
            
            self.login_cache[ip_privado] = None
            return None, None
            
        except Exception as e:
            logging.error(f"Erro no get_pppoe_login: {e}")
            try:
                self.conn.rollback()
            except:
                pass
            return None, None
        finally:
            cursor.close()
    
    def save_log(self, parsed: Dict):
        if not self.ensure_connection():
            return
            
        cursor = self.conn.cursor()
        try:
            login, sessao_id = self.get_pppoe_login(
                parsed['ip_privado'], 
                parsed['data_hora']
            )
            
            cursor.execute("""
                INSERT INTO cgnat_logs (
                    data_hora, acao, ip_privado, porta_privada,
                    ip_publico, porta_publica, ip_destino,
                    porta_destino, protocolo, login, sessao_id
                ) VALUES (
                    %s, %s, %s::inet, %s,
                    %s::inet, %s, %s::inet,
                    %s, %s, %s, %s
                )
            """, (
                parsed['data_hora'],
                parsed['acao'],
                parsed['ip_privado'],
                parsed['porta_privada'],
                parsed['ip_publico'],
                parsed['porta_publica'],
                parsed['ip_destino'],
                parsed['porta_destino'],
                parsed['protocolo'],
                login,
                sessao_id
            ))
            
            self.conn.commit()
            
            if parsed['acao'] == 'Created':
                self.stats['created'] += 1
            else:
                self.stats['deleted'] += 1
                
        except Exception as e:
            try:
                self.conn.rollback()
            except:
                pass
            self.stats['errors'] += 1
            logging.error(f"Erro ao salvar log: {e}")
        finally:
            cursor.close()
    
    def process_line(self, line: str):
        try:
            parsed = self.parse_log_line(line)
            if parsed:
                self.save_log(parsed)
            else:
                self.stats['errors'] += 1
        except Exception as e:
            self.stats['errors'] += 1
            logging.error(f"Erro processando linha: {e}")
    
    def run(self):
        logging.warning("Parser CGNAT iniciado - VERSÃO COM AUTO-RECONEXÃO")
        
        for line in sys.stdin:
            line = line.strip()
            if not line or '%NAT-6-LOG_TRANSLATION' not in line:
                continue
            self.process_line(line)
            
            if (self.stats['created'] + self.stats['deleted']) % 5000 == 0:
                logging.warning(f"Stats: Created={self.stats['created']}, Deleted={self.stats['deleted']}, Cache: hits={self.cache_hits}, misses={self.cache_misses}, Errors={self.stats['errors']}, Reconnects={self.stats['reconnects']}")

if __name__ == "__main__":
    parser = CGNATParserASR()
    parser.run()
EOF

chmod +x /opt/cgnat/cgnat_parser.py
print_success "Parser Python criado com auto-reconexão"

# ============================================================
# 11. CRIAR SERVICE DO PARSER (COM AUTO-RESTART)
# ============================================================
print_header "11. CRIANDO SERVICE DO PARSER"

cat > /etc/systemd/system/cgnat-parser.service << 'EOF'
[Unit]
Description=CGNAT Log Parser Service
After=network.target postgresql.service rsyslog.service
Wants=postgresql.service rsyslog.service

[Service]
Type=simple
User=root
Group=root
WorkingDirectory=/opt/cgnat
ExecStart=/bin/bash -c '/opt/cgnat/venv/bin/python /opt/cgnat/cgnat_parser.py < /var/run/cgnat.pipe'
Restart=always
RestartSec=5
StandardOutput=append:/var/log/cgnat/parser.log
StandardError=append:/var/log/cgnat/parser.error.log
CPUQuota=80%
Nice=-10
IOSchedulingClass=realtime
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cgnat-parser
print_success "Service do parser criado com auto-restart"

# ============================================================
# 12. CRIAR ARQUIVOS PHP
# ============================================================
print_header "12. CRIANDO ARQUIVOS PHP"

# 12.1 CONFIG.PHP
cat > /var/www/html/cgnat/config.php << CONFIG_PHP
<?php
define('DB_HOST', 'localhost');
define('DB_NAME', 'cgnat_logs');
define('DB_USER', 'cgnat_admin');
define('DB_PASS', '${DB_PASS_CGNAT}');
define('MK_AUTH_HOST', '${MK_AUTH_IP}');
define('MK_AUTH_DB', '${MK_AUTH_DB_TABLE}');
define('MK_AUTH_USER', '${MK_AUTH_USER}');
define('MK_AUTH_PASS', '${MK_AUTH_DB_PASS}');
date_default_timezone_set('${TIMEZONE}');
if (session_status() == PHP_SESSION_NONE) {
    session_start();
}
?>
CONFIG_PHP

# 12.2 HEADERS.PHP
cat > /var/www/html/cgnat/headers.php << 'HEADERS_PHP'
<?php
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Cache-Control: post-check=0, pre-check=0', false);
header('Pragma: no-cache');
header('Expires: Thu, 01 Jan 1970 00:00:00 GMT');
?>
HEADERS_PHP

# 12.3 FUNCTIONS.PHP
cat > /var/www/html/cgnat/functions.php << 'FUNCTIONS_PHP'
<?php
require_once 'config.php';

function getDBConnection() {
    try {
        $pdo = new PDO(
            "pgsql:host=" . DB_HOST . ";dbname=" . DB_NAME,
            DB_USER,
            DB_PASS
        );
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        return $pdo;
    } catch (PDOException $e) {
        die("Erro de conexão PostgreSQL: " . $e->getMessage());
    }
}

function getMKAUTHConnection() {
    try {
        $pdo = new PDO(
            "mysql:host=" . MK_AUTH_HOST . ";dbname=" . MK_AUTH_DB,
            MK_AUTH_USER,
            MK_AUTH_PASS
        );
        $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
        return $pdo;
    } catch (PDOException $e) {
        return null;
    }
}

function registrarAuditoria($usuario, $ip_publico, $porta, $motivo, $protocolo) {
    try {
        $db = getDBConnection();
        $stmt = $db->prepare("
            INSERT INTO lgpd_audit (
                usuario, ip_consultado, porta_consultada, 
                motivo, protocolo_judicial, data_consulta,
                ip_origem_consulta, user_agent
            ) VALUES (?, ?, ?, ?, ?, NOW(), ?, ?)
        ");
        $stmt->execute([
            $usuario,
            $ip_publico,
            $porta,
            $motivo,
            $protocolo,
            $_SERVER['REMOTE_ADDR'] ?? 'unknown',
            $_SERVER['HTTP_USER_AGENT'] ?? 'unknown'
        ]);
        return true;
    } catch (Exception $e) {
        error_log("Erro ao registrar auditoria: " . $e->getMessage());
        return false;
    }
}
?>
FUNCTIONS_PHP

# 12.4 AUTH.PHP
cat > /var/www/html/cgnat/auth.php << 'AUTH_PHP'
<?php
require_once 'config.php';
require_once 'functions.php';

function verificarLogin($usuario, $senha) {
    try {
        $db = getDBConnection();
        $stmt = $db->prepare("
            SELECT id, usuario, senha_hash, nome_completo, perfil, ativo
            FROM usuarios
            WHERE usuario = ? AND ativo = true
        ");
        $stmt->execute([$usuario]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        
        if (!$user) {
            return false;
        }
        
        if (password_verify($senha, $user['senha_hash'])) {
            if (session_status() == PHP_SESSION_NONE) {
                session_start();
            }
            
            $_SESSION['user_id'] = $user['id'];
            $_SESSION['usuario'] = $user['usuario'];
            $_SESSION['nome_completo'] = $user['nome_completo'] ?? $user['usuario'];
            $_SESSION['perfil'] = $user['perfil'];
            $_SESSION['logado'] = true;
            
            $stmt = $db->prepare("UPDATE usuarios SET ultimo_acesso = NOW() WHERE id = ?");
            $stmt->execute([$user['id']]);
            
            return true;
        }
        
        return false;
    } catch (Exception $e) {
        error_log("Erro no login: " . $e->getMessage());
        return false;
    }
}

function verificarPermissao($perfil_necessario = null) {
    if (session_status() == PHP_SESSION_NONE) {
        session_start();
    }
    
    if (!isset($_SESSION['usuario']) || !isset($_SESSION['logado'])) {
        header('Location: login.php');
        exit;
    }
    
    if ($perfil_necessario && $_SESSION['perfil'] != 'admin' && $_SESSION['perfil'] != $perfil_necessario) {
        header('Location: index.php?erro=permissao');
        exit;
    }
}
?>
AUTH_PHP

# 12.5 LOGIN.PHP
cat > /var/www/html/cgnat/login.php << 'LOGIN_PHP'
<?php
if (session_status() == PHP_SESSION_NONE) {
    session_start();
}

if (isset($_SESSION['usuario']) && isset($_SESSION['logado'])) {
    header('Location: index.php');
    exit;
}

require_once 'config.php';
require_once 'functions.php';
require_once 'auth.php';

$erro = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $usuario = $_POST['usuario'] ?? '';
    $senha = $_POST['senha'] ?? '';
    
    if (empty($usuario) || empty($senha)) {
        $erro = '❌ Preencha todos os campos.';
    } else {
        if (verificarLogin($usuario, $senha)) {
            header('Location: index.php');
            exit;
        } else {
            $erro = '❌ Usuário ou senha inválidos.';
        }
    }
}
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Login - CGNAT LGPD</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        .login-box {
            background: white;
            padding: 40px;
            border-radius: 15px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            width: 100%;
            max-width: 400px;
        }
        h1 {
            text-align: center;
            color: #333;
            margin-bottom: 30px;
        }
        h1 small {
            display: block;
            font-size: 14px;
            font-weight: normal;
            color: #888;
            margin-top: 5px;
        }
        .form-group { margin-bottom: 20px; }
        label { display: block; font-weight: 600; margin-bottom: 5px; color: #555; }
        input {
            width: 100%;
            padding: 12px;
            border: 2px solid #e0e0e0;
            border-radius: 8px;
            font-size: 14px;
        }
        input:focus { border-color: #667eea; outline: none; }
        .btn {
            width: 100%;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 15px;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
        }
        .btn:hover { transform: scale(1.02); }
        .alert {
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 20px;
            text-align: center;
        }
        .alert-danger { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .info {
            text-align: center;
            margin-top: 20px;
            font-size: 12px;
            color: #888;
        }
        .info span { 
            display: inline-block;
            background: #f0f0f0;
            padding: 2px 10px;
            border-radius: 4px;
            margin: 2px;
            color: #667eea;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="login-box">
        <h1>🔐 CGNAT LGPD <small>Sistema de Consulta</small></h1>
        <?php if ($erro): ?>
        <div class="alert alert-danger"><?php echo $erro; ?></div>
        <?php endif; ?>
        <form method="POST">
            <div class="form-group">
                <label>Usuário</label>
                <input type="text" name="usuario" required autofocus>
            </div>
            <div class="form-group">
                <label>Senha</label>
                <input type="password" name="senha" required>
            </div>
            <button type="submit" class="btn">Entrar</button>
        </form>
        <div class="info">Credenciais: <span>admin</span> <span>juridico</span> <span>operador</span></div>
    </div>
</body>
</html>
LOGIN_PHP

# 12.6 LOGOUT.PHP
cat > /var/www/html/cgnat/logout.php << 'LOGOUT_PHP'
<?php
session_start();
session_destroy();
header('Location: login.php');
exit;
?>
LOGOUT_PHP

# 12.7 MENU.PHP
cat > /var/www/html/cgnat/menu.php << 'MENU_PHP'
<?php
$current_page = basename($_SERVER['PHP_SELF']);
$usuario_nome = $_SESSION['nome_completo'] ?? $_SESSION['usuario'] ?? 'Usuário';
$perfil = $_SESSION['perfil'] ?? 'operador';
?>
<style>
.navbar-cgnat {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    padding: 10px 20px;
    border-radius: 8px;
    margin-bottom: 20px;
    display: flex;
    justify-content: space-between;
    align-items: center;
    flex-wrap: wrap;
}
.navbar-cgnat .logo { font-size: 20px; font-weight: bold; color: white; text-decoration: none; }
.navbar-cgnat .nav-links { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
.navbar-cgnat .nav-links a {
    color: rgba(255,255,255,0.8);
    text-decoration: none;
    padding: 6px 12px;
    border-radius: 5px;
    transition: all 0.3s;
    font-size: 14px;
}
.navbar-cgnat .nav-links a:hover { background: rgba(255,255,255,0.2); color: white; }
.navbar-cgnat .nav-links a.active { background: rgba(255,255,255,0.25); color: white; }
.navbar-cgnat .nav-links .user-info { color: rgba(255,255,255,0.9); padding: 6px 12px; font-size: 13px; }
.navbar-cgnat .nav-links .logout-btn {
    background: #dc3545;
    color: white;
    padding: 6px 15px;
    border-radius: 5px;
    text-decoration: none;
    font-size: 13px;
}
.navbar-cgnat .nav-links .logout-btn:hover { background: #c82333; }
@media (max-width: 768px) {
    .navbar-cgnat { flex-direction: column; gap: 10px; }
    .navbar-cgnat .nav-links { justify-content: center; }
}
</style>
<div class="navbar-cgnat">
    <a href="index.php" class="logo">📡 WEBLINE TELECOM - LGPD LOGS SERVER</a>
    <div class="nav-links">
        <span class="user-info">👤 <?php echo htmlspecialchars($usuario_nome); ?></span>
        <a href="index.php" class="<?php echo $current_page == 'index.php' ? 'active' : ''; ?>">🏠 Início</a>
        <a href="dashboard.php" class="<?php echo $current_page == 'dashboard.php' ? 'active' : ''; ?>">📊 Dashboard</a>
        <a href="consultar.php" class="<?php echo $current_page == 'consultar.php' ? 'active' : ''; ?>">🔍 Consultar</a>
        <?php if ($perfil == 'admin' || $perfil == 'juridico'): ?>
        <a href="relatorios.php" class="<?php echo $current_page == 'relatorios.php' ? 'active' : ''; ?>">📋 Relatórios</a>
        <?php endif; ?>
        <?php if ($perfil == 'admin'): ?>
        <a href="admin.php" class="<?php echo $current_page == 'admin.php' ? 'active' : ''; ?>">⚙️ Admin</a>
        <?php endif; ?>
        <a href="logout.php" class="logout-btn">🚪 Sair</a>
    </div>
</div>
MENU_PHP

cat > /var/www/html/cgnat/index.php << 'INDEX_PHP'
<?php
require_once 'headers.php';
require_once 'auth.php';
verificarPermissao();
require_once 'functions.php';

$db = getDBConnection();

$stmt = $db->query("SELECT total FROM vw_cgnat_logs_count");
$total_logs = $stmt->fetchColumn();

$stmt = $db->query("SELECT COUNT(*) FROM clientes");
$total_clientes = $stmt->fetchColumn();

$stmt = $db->query("SELECT COUNT(*) FROM lgpd_audit WHERE DATE(data_consulta) = CURRENT_DATE");
$consultas_hoje = $stmt->fetchColumn();

// Buscar espaço em disco
$disco_info = shell_exec("df -h / | grep -v Filesystem | awk '{print $2,$3,$4,$5}'");
$disco_parts = preg_split('/\s+/', trim($disco_info));
$disco_total = $disco_parts[0] ?? 'N/A';
$disco_usado = $disco_parts[1] ?? 'N/A';
$disco_livre = $disco_parts[2] ?? 'N/A';
$disco_uso = $disco_parts[3] ?? 'N/A';

// Buscar tamanho do banco
try {
    $stmt = $db->query("SELECT pg_size_pretty(pg_database_size('cgnat_logs')) as tamanho");
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
    $tamanho_db = $result['tamanho'] ?? 'N/A';
} catch (Exception $e) {
    $tamanho_db = 'N/A';
}

// ============================================================
// CALCULAR TEMPO ONLINE DO SISTEMA
// ============================================================
function getUptime() {
    // Pegar uptime do sistema
    $uptime = shell_exec("cat /proc/uptime");
    $uptime = explode(" ", $uptime);
    $seconds = intval($uptime[0]);
    
    $days = floor($seconds / 86400);
    $seconds -= $days * 86400;
    $hours = floor($seconds / 3600);
    $seconds -= $hours * 3600;
    $minutes = floor($seconds / 60);
    $seconds -= $minutes * 60;
    
    $result = '';
    if ($days > 0) {
        $result .= $days . 'd ';
    }
    $result .= sprintf("%02dh %02dm %02ds", $hours, $minutes, $seconds);
    
    // Pegar data/hora do boot
    $boot_time = shell_exec("date -d @$(($(date +%s) - $(cat /proc/uptime | cut -d' ' -f1 | cut -d'.' -f1))) '+%d/%m/%Y %H:%M:%S'");
    
    return [
        'uptime' => $result,
        'boot' => trim($boot_time)
    ];
}

$uptime_info = getUptime();

include 'menu.php';
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CGNAT LGPD - Início</title>
    <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
    <meta http-equiv="Pragma" content="no-cache">
    <meta http-equiv="Expires" content="0">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; }

        .header-index {
            display: flex;
            justify-content: space-between;
            align-items: center;
            background: white;
            border-radius: 12px;
            padding: 20px 30px;
            box-shadow: 0 2px 12px rgba(0,0,0,0.08);
            margin-bottom: 30px;
            flex-wrap: wrap;
            gap: 15px;
        }
        .header-index .welcome h1 {
            color: #333;
            font-size: 22px;
            font-weight: 600;
        }
        .header-index .welcome h1 .user {
            color: #667eea;
            font-weight: 700;
        }
        .header-index .welcome p {
            color: #888;
            font-size: 14px;
            margin-top: 2px;
        }
        .header-index .welcome .perfil {
            color: #aaa;
            font-size: 13px;
            margin-top: 2px;
        }
        .header-index .welcome .uptime {
            color: #27ae60;
            font-size: 13px;
            margin-top: 5px;
            background: #e8f5e9;
            padding: 4px 12px;
            border-radius: 20px;
            display: inline-block;
        }
        .header-index .welcome .uptime .label {
            color: #888;
        }
        .header-index .welcome .uptime .time {
            font-weight: 700;
            color: #27ae60;
        }

        .disco-card-header {
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
            border-radius: 12px;
            padding: 14px 24px;
            min-width: 180px;
            border: 1px solid #e9ecef;
            text-align: center;
            flex-shrink: 0;
            box-shadow: 0 1px 4px rgba(0,0,0,0.04);
        }
        .disco-card-header .numero {
            font-size: 28px;
            font-weight: 700;
            color: #333;
        }
        .disco-card-header .numero .total {
            font-size: 18px;
            color: #bbb;
            font-weight: 400;
        }
        .disco-card-header .barra {
            width: 100%;
            height: 6px;
            background: #dee2e6;
            border-radius: 4px;
            overflow: hidden;
            margin: 8px 0 6px 0;
        }
        .disco-card-header .barra-fill {
            height: 100%;
            border-radius: 4px;
            transition: width 0.6s ease;
        }
        .disco-card-header .barra-fill.verde { background: linear-gradient(90deg, #27ae60, #2ecc71); }
        .disco-card-header .barra-fill.amarelo { background: linear-gradient(90deg, #f39c12, #f1c40f); }
        .disco-card-header .barra-fill.vermelho { background: linear-gradient(90deg, #e74c3c, #c0392b); }
        .disco-card-header .label {
            color: #888;
            font-size: 13px;
            font-weight: 500;
            margin-top: 2px;
        }
        .disco-card-header .detalhes {
            font-size: 12px;
            color: #aaa;
            margin-top: 3px;
            display: flex;
            justify-content: center;
            gap: 12px;
        }
        .disco-card-header .detalhes .db {
            border-left: 1px solid #ddd;
            padding-left: 12px;
        }

        .cards {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 20px;
            margin-bottom: 30px;
        }
        .card {
            background: white;
            padding: 22px 15px;
            border-radius: 12px;
            box-shadow: 0 2px 12px rgba(0,0,0,0.08);
            text-align: center;
            transition: transform 0.2s ease, box-shadow 0.2s ease;
        }
        .card:hover {
            transform: translateY(-3px);
            box-shadow: 0 4px 20px rgba(0,0,0,0.12);
        }
        .card .numero {
            font-size: 30px;
            font-weight: 700;
            color: #667eea;
        }
        .card .label {
            color: #888;
            margin-top: 6px;
            font-size: 14px;
            font-weight: 500;
        }
        .card-verde .numero { color: #27ae60; }
        .card-vermelho .numero { color: #e74c3c; }
        .card-amarelo .numero { color: #f39c12; }

        .btn-consulta {
            display: inline-block;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 16px 48px;
            border-radius: 10px;
            font-size: 17px;
            font-weight: 600;
            cursor: pointer;
            text-decoration: none;
            transition: transform 0.2s ease, box-shadow 0.2s ease;
            box-shadow: 0 4px 15px rgba(102, 126, 234, 0.3);
            margin-top: 10px;
        }
        .btn-consulta:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 25px rgba(102, 126, 234, 0.4);
        }
        .actions { text-align: center; margin-top: 20px; }

        .footer-info {
            margin-top: 30px;
            padding: 15px 20px;
            background: white;
            border-radius: 12px;
            box-shadow: 0 2px 12px rgba(0,0,0,0.08);
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 10px;
            font-size: 13px;
            color: #888;
        }
        .footer-info .uptime-footer {
            color: #555;
        }
        .footer-info .uptime-footer strong {
            color: #27ae60;
        }
        .footer-info .version {
            color: #aaa;
        }

        @media (max-width: 768px) {
            .cards { grid-template-columns: 1fr 1fr; }
            .header-index { flex-direction: column; align-items: stretch; }
            .disco-card-header { align-self: stretch; }
            .footer-info { flex-direction: column; text-align: center; }
        }
        @media (max-width: 480px) {
            .cards { grid-template-columns: 1fr; }
            .disco-card-header .numero { font-size: 24px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header-index">
            <div class="welcome">
                <h1>👋 Bem-vindo, <span class="user"><?php echo htmlspecialchars($_SESSION['nome_completo']); ?></span></h1>
                <p>Sistema de Consulta CGNAT para atendimento à LGPD.</p>
                <div class="perfil">Perfil: <strong><?php echo htmlspecialchars($_SESSION['perfil']); ?></strong></div>
                <!-- ============================================================
                     COMENTAR ESTE BLOCO - HEADER (UPTIME)
                     ============================================================ -->
                <!--
                <div class="uptime">
                <span class="label">🟢 Online há </span>
                <span class="time" id="uptime_display"><?php echo $uptime_info['uptime']; ?></span>
                <span style="color:#aaa;font-size:11px;margin-left:8px;">(desde <?php echo $uptime_info['boot']; ?>)</span>
                </div>
                -->
            </div>

            <div class="disco-card-header">
                <div class="numero">
                    <?php echo $disco_usado; ?> <span class="total">/ <?php echo $disco_total; ?></span>
                </div>
                <div class="barra">
                    <?php 
                    $percentual = (int)str_replace('%', '', $disco_uso);
                    $cor = $percentual < 70 ? 'verde' : ($percentual < 85 ? 'amarelo' : 'vermelho');
                    ?>
                    <div class="barra-fill <?php echo $cor; ?>" style="width: <?php echo min($percentual, 100); ?>%;"></div>
                </div>
                <div class="label">💾 Uso de Disco</div>
                <div class="detalhes">
                    <span><?php echo $disco_uso; ?></span>
                    <span class="db">🗄️ <?php echo $tamanho_db; ?></span>
                </div>
            </div>
        </div>

        <div class="cards">
            <div class="card card-verde">
                <div class="numero"><?php echo $consultas_hoje; ?></div>
                <div class="label">📋 Consultas Hoje</div>
            </div>
            <div class="card card-vermelho">
                <div class="numero" id="total_logs"><?php echo number_format($total_logs); ?></div>
                <div class="label">📊 Total de Logs CGNAT</div>
            </div>
            <div class="card card-amarelo">
                <div class="numero"><?php echo number_format($total_clientes); ?></div>
                <div class="label">👥 Clientes Cadastrados</div>
            </div>
            <div class="card">
                <div class="numero"><?php echo date('d/m/Y'); ?></div>
                <div class="label">📅 Data Atual</div>
            </div>
        </div>

        <div class="actions">
            <a href="consultar.php" class="btn-consulta">🔍 Ir para Consultas</a>
        </div>

        <div class="footer-info">
            <div class="uptime-footer">
                🟢 <strong>Online:</strong> 
                <span id="uptime_footer"><?php echo $uptime_info['uptime']; ?></span>
                <span style="color:#aaa;font-size:11px;">(boot: <?php echo $uptime_info['boot']; ?>)</span>
            </div>
            <div class="version">
                📡 WEBLINE TELECOM - LGPD CGNAT LOGS v1.0
            </div>
        </div>
    </div>

    <script>
    // ============================================================
    // ATUALIZAR CONTADOR DE TEMPO ONLINE EM TEMPO REAL
    // ============================================================
    (function() {
        // Pegar o uptime inicial em segundos
        var initialUptime = <?php echo intval(file_get_contents('/proc/uptime')); ?>;
        var startTime = Date.now() - (initialUptime * 1000);
        
        function formatUptime(seconds) {
            var days = Math.floor(seconds / 86400);
            seconds -= days * 86400;
            var hours = Math.floor(seconds / 3600);
            seconds -= hours * 3600;
            var minutes = Math.floor(seconds / 60);
            seconds -= minutes * 60;
            
            var result = '';
            if (days > 0) {
                result += days + 'd ';
            }
            result += String(hours).padStart(2, '0') + 'h ';
            result += String(minutes).padStart(2, '0') + 'm ';
            result += String(Math.floor(seconds)).padStart(2, '0') + 's';
            return result;
        }
        
        function updateUptime() {
            var now = Date.now();
            var uptimeSeconds = (now - startTime) / 1000;
            var formatted = formatUptime(uptimeSeconds);
            
            // Atualizar todos os elementos
            var displays = document.querySelectorAll('#uptime_display, #uptime_footer');
            displays.forEach(function(el) {
                if (el) el.textContent = formatted;
            });
        }
        
        // Atualizar a cada 1 segundo
        setInterval(updateUptime, 1000);
        
        // Atualizar imediatamente
        updateUptime();
    })();
    
    // Auto-refresh a cada 5 segundos (para outros dados)
    setTimeout(function() {
        location.reload();
    }, 5000);
    </script>
</body>
</html>
INDEX_PHP

# 12.9 DASHBOARD.PHP
cat > /var/www/html/cgnat/dashboard.php << 'DASHBOARD_PHP'
<?php
require_once 'headers.php';
require_once 'auth.php';
verificarPermissao();
require_once 'functions.php';

$db = getDBConnection();

$stmt = $db->query("SELECT COUNT(*) FROM lgpd_audit WHERE DATE(data_consulta) = CURRENT_DATE");
$hoje = $stmt->fetchColumn();

$stmt = $db->query("SELECT COUNT(*) FROM lgpd_audit WHERE data_consulta > NOW() - INTERVAL '7 days'");
$semana = $stmt->fetchColumn();

$stmt = $db->query("SELECT COUNT(*) FROM lgpd_audit WHERE data_consulta > NOW() - INTERVAL '30 days'");
$mes = $stmt->fetchColumn();

$stmt = $db->query("SELECT COUNT(*) FROM cgnat_logs");
$total_logs = $stmt->fetchColumn();

$stmt = $db->query("SELECT COUNT(*) FROM clientes");
$total_clientes = $stmt->fetchColumn();

// Buscar espaço em disco
$disco_info = shell_exec("df -h / | grep -v Filesystem | awk '{print $2,$3,$4,$5}'");
$disco_parts = preg_split('/\s+/', trim($disco_info));
$disco_total = $disco_parts[0] ?? 'N/A';
$disco_usado = $disco_parts[1] ?? 'N/A';
$disco_livre = $disco_parts[2] ?? 'N/A';
$disco_uso = $disco_parts[3] ?? 'N/A';

// Buscar tamanho do banco
try {
    $stmt = $db->query("SELECT pg_size_pretty(pg_database_size('cgnat_logs')) as tamanho");
    $result = $stmt->fetch(PDO::FETCH_ASSOC);
    $tamanho_db = $result['tamanho'] ?? 'N/A';
} catch (Exception $e) {
    $tamanho_db = 'N/A';
}

// Buscar últimas consultas
$stmt = $db->query("
    SELECT 
        usuario,
        ip_consultado,
        porta_consultada,
        data_consulta,
        cliente_nome,
        ip_privado,
        ipv6_cliente,
        log_data_hora,
        log_acao,
        resultado_registros
    FROM lgpd_audit 
    ORDER BY data_consulta DESC 
    LIMIT 10
");
$ultimas = $stmt->fetchAll(PDO::FETCH_ASSOC);

include 'menu.php';
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard CGNAT</title>
    <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
    <meta http-equiv="Pragma" content="no-cache">
    <meta http-equiv="Expires" content="0">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 10px; padding: 30px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        
        .header-dashboard {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 30px;
            flex-wrap: wrap;
            gap: 10px;
        }
        .header-dashboard h1 {
            color: #333;
            margin: 0;
            font-size: 28px;
        }
        .disco-indicator {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 13px;
            color: #888;
            background: #f8f9fa;
            padding: 5px 14px;
            border-radius: 20px;
            border: 1px solid #e9ecef;
        }
        .disco-indicator .barra-mini {
            width: 60px;
            height: 5px;
            background: #e9ecef;
            border-radius: 3px;
            overflow: hidden;
        }
        .disco-indicator .barra-mini-fill {
            height: 100%;
            border-radius: 3px;
            transition: width 0.3s;
        }
        .disco-indicator .barra-mini-fill.verde { background: #27ae60; }
        .disco-indicator .barra-mini-fill.amarelo { background: #f39c12; }
        .disco-indicator .barra-mini-fill.vermelho { background: #e74c3c; }
        .disco-indicator .uso { font-weight: 600; color: #555; }
        .disco-indicator .db { color: #bbb; font-size: 11px; border-left: 1px solid #eee; padding-left: 8px; }

        .row { display: grid; grid-template-columns: 1fr 1fr 1fr 1fr; gap: 20px; margin-bottom: 30px; }
        .card { background: #f8f9fa; padding: 20px; border-radius: 10px; text-align: center; }
        .card .numero { font-size: 32px; font-weight: bold; color: #667eea; }
        .card .label { color: #888; margin-top: 5px; font-size: 14px; }
        .card-verde .numero { color: #27ae60; }
        .card-vermelho .numero { color: #e74c3c; }
        .card-amarelo .numero { color: #f39c12; }

        table {
            width: 100%;
            border-collapse: collapse;
            margin-top: 15px;
            font-size: 14px;
        }
        th { 
            background: #f8f9fa; 
            padding: 12px; 
            text-align: left; 
            border-bottom: 2px solid #dee2e6; 
            font-size: 14px;
            font-weight: 600;
        }
        td { 
            padding: 10px; 
            border-bottom: 1px solid #eee; 
            font-size: 14px;
            vertical-align: middle;
        }
        .badge-info { background: #cce5ff; color: #004085; padding: 4px 12px; border-radius: 20px; font-size: 13px; font-weight: 600; display: inline-block; }
        .badge-success { background: #d4edda; color: #155724; padding: 4px 12px; border-radius: 20px; font-size: 13px; font-weight: 600; display: inline-block; }
        .badge-danger { background: #f8d7da; color: #721c24; padding: 4px 12px; border-radius: 20px; font-size: 13px; font-weight: 600; display: inline-block; }
        .badge-ipv6 { background: #d1ecf1; color: #0c5460; padding: 4px 12px; border-radius: 20px; font-size: 11px; font-weight: 600; display: inline-block; font-family: monospace; }
        .text-muted { color: #999; }
        .log-info { font-size: 14px; color: #888; white-space: nowrap; }

        @media (max-width: 768px) { 
            .row { grid-template-columns: 1fr 1fr; }
            .header-dashboard { flex-direction: column; align-items: flex-start; }
            .disco-indicator { align-self: flex-start; }
            table { font-size: 12px; }
            th, td { padding: 6px; font-size: 12px; }
            .badge-info, .badge-success, .badge-danger { font-size: 11px; padding: 2px 8px; }
            .log-info { font-size: 12px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header-dashboard">
            <h1>📊 Dashboard CGNAT</h1>
            <div class="disco-indicator">
                <span>💾</span>
                <span class="uso"><?php echo $disco_usado; ?></span>
                <span>/ <?php echo $disco_total; ?></span>
                <div class="barra-mini">
                    <?php 
                    $percentual = (int)str_replace('%', '', $disco_uso);
                    $cor = $percentual < 70 ? 'verde' : ($percentual < 85 ? 'amarelo' : 'vermelho');
                    ?>
                    <div class="barra-mini-fill <?php echo $cor; ?>" style="width: <?php echo min($percentual, 100); ?>%;"></div>
                </div>
                <span style="font-size:11px;color:#888;"><?php echo $disco_uso; ?></span>
                <span class="db">DB: <?php echo $tamanho_db; ?></span>
            </div>
        </div>

        <div class="row">
            <div class="card card-verde"><div class="numero"><?php echo $hoje; ?></div><div class="label">Consultas Hoje</div></div>
            <div class="card card-amarelo"><div class="numero"><?php echo $semana; ?></div><div class="label">Consultas (7 dias)</div></div>
            <div class="card"><div class="numero"><?php echo $mes; ?></div><div class="label">Consultas (30 dias)</div></div>
            <div class="card card-vermelho"><div class="numero" id="total_logs"><?php echo number_format($total_logs); ?></div><div class="label">Total Logs CGNAT</div></div>
        </div>

        <div style="margin-top:30px;">
            <h3 style="font-size:18px;margin-bottom:15px;">📋 Últimas Consultas</h3>
            <div style="overflow-x:auto;">
                <table>
                    <thead>
                        <tr>
                            <th>Data</th>
                            <th>Usuário</th>
                            <th>IP</th>
                            <th>Porta</th>
                            <th>Cliente</th>
                            <th>IPv4</th>
                            <th>IPv6</th>
                            <th>Log Original</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php if ($ultimas): ?>
                            <?php foreach ($ultimas as $row): ?>
                            <tr>
                                <td style="white-space:nowrap;"><?php echo date('d/m/Y H:i', strtotime($row['data_consulta'])); ?></td>
                                <td><?php echo htmlspecialchars($row['usuario']); ?></td>
                                <td><strong><?php echo htmlspecialchars($row['ip_consultado'] ?? '-'); ?></strong></td>
                                <td><?php echo htmlspecialchars($row['porta_consultada'] ?? '-'); ?></td>
                                <td>
                                    <?php if (!empty($row['cliente_nome'])): ?>
                                        <span class="badge-info"><?php echo htmlspecialchars($row['cliente_nome']); ?></span>
                                    <?php else: ?>
                                        <span class="text-muted">-</span>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo htmlspecialchars($row['ip_privado'] ?? '-'); ?></td>
                                <td>
                                    <?php if (!empty($row['ipv6_cliente'])): ?>
                                        <span class="badge-ipv6"><?php echo htmlspecialchars($row['ipv6_cliente']); ?></span>
                                    <?php else: ?>
                                        <span class="text-muted">-</span>
                                    <?php endif; ?>
                                </td>
                                <td class="log-info">
                                    <?php if ($row['log_acao']): ?>
                                        <span class="badge <?php echo $row['log_acao'] == 'Created' ? 'badge-success' : 'badge-danger'; ?>">
                                            <?php echo $row['log_acao'] == 'Created' ? '📌 Criação' : '❌ Deleção'; ?>
                                        </span>
                                        <?php echo date('d/m/Y H:i', strtotime($row['log_data_hora'])); ?>
                                    <?php else: ?>
                                        <span class="text-muted">-</span>
                                    <?php endif; ?>
                                </td>
                            </tr>
                            <?php endforeach; ?>
                        <?php else: ?>
                            <tr><td colspan="8" style="text-align:center;color:#999;padding:20px;">Nenhuma consulta realizada</td></tr>
                        <?php endif; ?>
                    </tbody>
                </table>
            </div>
        </div>
    </div>
    
    <script>
    setTimeout(function() {
        location.reload();
    }, 15000);
    </script>
</body>
</html>
DASHBOARD_PHP

# 12.10 CONSULTAR.PHP
cat > /var/www/html/cgnat/consultar.php << 'CONSULTAR_PHP'
<?php
require_once 'headers.php';
require_once 'auth.php';
verificarPermissao();
require_once 'functions.php';

date_default_timezone_set('America/Recife');

function identificarTipoIP($ip) {
    if (empty($ip)) {
        return ['tipo' => 'desconhecido', 'label' => 'Desconhecido', 'class' => ''];
    }
    
    $ip_long = ip2long($ip);
    if ($ip_long === false) {
        return ['tipo' => 'invalido', 'label' => 'IP Inválido', 'class' => ''];
    }
    
    if ($ip_long >= ip2long('100.64.0.0') && $ip_long <= ip2long('100.127.255.255')) {
        return ['tipo' => 'cgnat', 'label' => 'IPv4 CGNAT', 'class' => 'badge-cgnat'];
    }
    
    if ($ip_long >= ip2long('10.0.0.0') && $ip_long <= ip2long('10.255.255.255')) {
        return ['tipo' => 'privado', 'label' => 'IPv4 Privado', 'class' => 'badge-privado'];
    }
    
    if ($ip_long >= ip2long('172.16.0.0') && $ip_long <= ip2long('172.31.255.255')) {
        return ['tipo' => 'privado', 'label' => 'IPv4 Privado', 'class' => 'badge-privado'];
    }
    
    if ($ip_long >= ip2long('192.168.0.0') && $ip_long <= ip2long('192.168.255.255')) {
        return ['tipo' => 'privado', 'label' => 'IPv4 Privado', 'class' => 'badge-privado'];
    }
    
    if ($ip_long >= ip2long('127.0.0.0') && $ip_long <= ip2long('127.255.255.255')) {
        return ['tipo' => 'loopback', 'label' => 'Loopback', 'class' => 'badge-loopback'];
    }
    
    if ($ip_long >= ip2long('169.254.0.0') && $ip_long <= ip2long('169.254.255.255')) {
        return ['tipo' => 'linklocal', 'label' => 'Link-local', 'class' => 'badge-linklocal'];
    }
    
    return ['tipo' => 'publico', 'label' => 'IPv4 Público', 'class' => 'badge-publico'];
}

$resultados = null;
$total = 0;
$mensagem = '';
$cliente_nome = '';
$ip_privado = '';
$ipv6_prefix = '';
$log_data_hora = '';
$log_acao = '';
$log_destino = '';
$log_protocolo = '';
$cliente_encontrado = false;
$cliente_login = '';
$tipo_ip_info = null;

$data_atual = date('Y-m-d');

if ($_SERVER['REQUEST_METHOD'] === 'GET' && (isset($_GET['ip_publico']) || isset($_GET['ipv6_busca']))) {
    $_POST['ip_publico'] = $_GET['ip_publico'] ?? '';
    $_POST['porta'] = $_GET['porta'] ?? '';
    $_POST['ipv6_busca'] = $_GET['ipv6_busca'] ?? '';
    $_POST['data_inicio'] = $_GET['data_inicio'] ?? $data_atual;
    $_POST['data_fim'] = $_GET['data_fim'] ?? $data_atual;
    $_POST['hora_inicio'] = $_GET['hora_inicio'] ?? '00:00';
    $_POST['hora_fim'] = $_GET['hora_fim'] ?? '23:59';
    $_POST['motivo'] = $_GET['motivo'] ?? 'Reabertura de consulta';
    $_POST['protocolo'] = $_GET['protocolo'] ?? '';
    
    $_SERVER['REQUEST_METHOD'] = 'POST';
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $ip_publico = trim($_POST['ip_publico'] ?? '');
    $porta = trim($_POST['porta'] ?? '');
    $ipv6_busca = trim($_POST['ipv6_busca'] ?? '');
    $data_inicio = $_POST['data_inicio'] . ' ' . ($_POST['hora_inicio'] ?? '00:00:00');
    $data_fim = $_POST['data_fim'] . ' ' . ($_POST['hora_fim'] ?? '23:59:59');
    $motivo = $_POST['motivo'] ?? 'Consulta LGPD';
    $protocolo = $_POST['protocolo'] ?? '';
    
    if (empty($ip_publico) && empty($ipv6_busca)) {
        $mensagem = '⚠️ Preencha pelo menos o IP Público + Porta, ou o IPv6.';
    } elseif (!empty($ip_publico) && empty($porta)) {
        $mensagem = '⚠️ Se informar o IP Público, a Porta Pública é obrigatória.';
    } else {
        try {
            $db = getDBConnection();
            
            if (!empty($ip_publico) && !empty($porta)) {
                $sql = "
                    SELECT 
                        c.data_hora,
                        c.acao,
                        c.ip_privado,
                        c.porta_privada,
                        c.ip_publico,
                        c.porta_publica,
                        c.ip_destino,
                        c.porta_destino,
                        c.protocolo,
                        c.ipv6_cliente,
                        COALESCE(cl.nome, c.login) as cliente_nome,
                        c.login as cliente_login,
                        cl.ipv6_prefix,
                        cl.nome as cliente_nome_real
                    FROM cgnat_logs c
                    LEFT JOIN clientes cl ON c.login = cl.login
                    WHERE c.ip_publico = ?::inet 
                    AND c.porta_publica = ?
                    AND c.data_hora BETWEEN ? AND ?
                    ORDER BY c.data_hora DESC 
                    LIMIT 1000
                ";
                
                $params = [$ip_publico, (int)$porta, $data_inicio, $data_fim];
                $stmt = $db->prepare($sql);
                $stmt->execute($params);
                $resultados = $stmt->fetchAll(PDO::FETCH_ASSOC);
                $total = count($resultados);
                
                if ($total > 0) {
                    $primeiro = $resultados[0];
                    $cliente_nome = $primeiro['cliente_nome'] ?? 'Nao identificado';
                    $cliente_login = $primeiro['cliente_login'] ?? '';
                    $ip_privado = $primeiro['ip_privado'] ?? null;
                    $ipv6_prefix = $primeiro['ipv6_prefix'] ?? null;
                    $log_data_hora = $primeiro['data_hora'] ?? null;
                    $log_acao = $primeiro['acao'] ?? null;
                    $log_destino = ($primeiro['ip_destino'] ?? '') . ':' . ($primeiro['porta_destino'] ?? '');
                    $log_protocolo = $primeiro['protocolo'] ?? null;
                    $cliente_encontrado = true;
                    
                    if ($ip_privado) {
                        $tipo_ip_info = identificarTipoIP($ip_privado);
                    }
                }
                
                $mensagem = $total > 0 ? "✅ Encontrados {$total} registros CGNAT." : '⚠️ Nenhum registro CGNAT encontrado.';
            }
            
            if (!empty($ipv6_busca)) {
                $ipv6_normalizado = $ipv6_busca;
                
                $ipv6_clean = preg_replace('/\/\d+$/', '', $ipv6_busca);
                
                if (strpos($ipv6_clean, '::') !== false) {
                    $parts = explode(':', $ipv6_clean);
                    $count = count(array_filter($parts, 'strlen'));
                    $missing = 8 - $count;
                    $ipv6_clean = str_replace('::', ':' . str_repeat('0000:', $missing), $ipv6_clean);
                    $ipv6_clean = rtrim($ipv6_clean, ':');
                }
                
                $parts = explode(':', $ipv6_clean);
                while (count($parts) < 8) {
                    $parts[] = '0000';
                }
                
                $prefixo_parts = array_slice($parts, 0, 4);
                $prefixo = implode(':', $prefixo_parts) . '::/56';
                $ipv6_normalizado = $prefixo;
                
                $sql = "
                    SELECT 
                        h.login,
                        h.ipv6_prefix,
                        h.data_inicio,
                        h.data_fim,
                        h.ativo,
                        c.nome,
                        c.ip_privado,
                        c.ipv6_address
                    FROM historico_ipv6 h
                    LEFT JOIN clientes c ON h.login = c.login
                    WHERE UPPER(h.ipv6_prefix) = UPPER(?)
                    AND h.data_inicio <= ?
                    AND (h.data_fim IS NULL OR h.data_fim >= ?)
                    LIMIT 1
                ";
                
                $stmt = $db->prepare($sql);
                $stmt->execute([$ipv6_normalizado, $data_fim, $data_inicio]);
                $historico = $stmt->fetch(PDO::FETCH_ASSOC);
                
                if ($historico) {
                    $cliente_encontrado = true;
                    $cliente_login = $historico['login'] ?? '';
                    $cliente_nome = $historico['nome'] ?? $cliente_login;
                    $ip_privado = $historico['ip_privado'] ?? null;
                    $ipv6_prefix = $historico['ipv6_prefix'] ?? null;
                    
                    if ($ip_privado) {
                        $tipo_ip_info = identificarTipoIP($ip_privado);
                    }
                    
                    if ($ip_privado) {
                        $sql_logs = "
                            SELECT 
                                data_hora,
                                acao,
                                ip_publico,
                                porta_publica,
                                ip_destino,
                                porta_destino,
                                protocolo,
                                ipv6_cliente
                            FROM cgnat_logs
                            WHERE ip_privado = ?::inet
                            AND data_hora BETWEEN ? AND ?
                            ORDER BY data_hora DESC
                            LIMIT 50
                        ";
                        $stmt_logs = $db->prepare($sql_logs);
                        $stmt_logs->execute([$ip_privado, $data_inicio, $data_fim]);
                        $resultados = $stmt_logs->fetchAll(PDO::FETCH_ASSOC);
                        $total = count($resultados);
                    } else {
                        $resultados = [];
                        $total = 0;
                    }
                    
                    $periodo = date('d/m/Y H:i', strtotime($historico['data_inicio']));
                    if ($historico['data_fim']) {
                        $periodo .= " até " . date('d/m/Y H:i', strtotime($historico['data_fim']));
                    } else {
                        $periodo .= " até o momento";
                    }
                    
                    $mensagem = "✅ Cliente identificado por IPv6: <strong>" . htmlspecialchars($cliente_nome) . "</strong>";
                    $mensagem .= " | Login: <code>" . htmlspecialchars($cliente_login) . "</code>";
                    $mensagem .= " | Prefixo: <code>" . htmlspecialchars($ipv6_prefix) . "</code>";
                    $mensagem .= "<br>📅 Período do prefixo: " . $periodo;
                    
                    if ($total > 0) {
                        $mensagem .= "<br>📊 Possui {$total} registros CGNAT no período consultado.";
                    } else {
                        $mensagem .= "<br>ℹ️ Cliente não possui logs CGNAT no período consultado.";
                    }
                    
                } else {
                    $cliente_encontrado = false;
                    $cliente_nome = 'NAO IDENTIFICADO - Cliente sem IPv6 no período';
                    $cliente_login = '';
                    $ip_privado = null;
                    $ipv6_prefix = $ipv6_normalizado;
                    $tipo_ip_info = null;
                    $resultados = [];
                    $total = 0;
                    $mensagem = "⚠️ Nenhum cliente encontrado com o prefixo IPv6: <code>" . htmlspecialchars($ipv6_normalizado) . "</code>";
                    $mensagem .= "<br><small>Verifique se o cliente usou este prefixo no período consultado.</small>";
                    $mensagem .= "<br><small>O prefixo pode ter sido atribuído depois desta data.</small>";
                }
            }
            
            $ip_publico_sql = !empty($ip_publico) ? $ip_publico : null;
            $porta_sql = !empty($porta) ? (int)$porta : null;
            $ip_privado_sql = !empty($ip_privado) ? $ip_privado : null;
            $ipv6_prefix_sql = !empty($ipv6_prefix) ? $ipv6_prefix : null;
            $ip_origem = !empty($_SERVER['REMOTE_ADDR']) ? $_SERVER['REMOTE_ADDR'] : null;
            
            if (!empty($ipv6_busca)) {
                $ip_consultado = $ipv6_normalizado;
                $porta_sql = null;
            } else {
                $ip_consultado = $ip_publico_sql;
            }
            
            $log_data_hora_sql = !empty($log_data_hora) ? $log_data_hora : null;
            $log_acao_sql = !empty($log_acao) ? $log_acao : null;
            $log_destino_sql = !empty($log_destino) ? $log_destino : null;
            $log_protocolo_sql = !empty($log_protocolo) ? $log_protocolo : null;
            
            $stmt = $db->prepare("
                INSERT INTO lgpd_audit (
                    usuario, 
                    ip_consultado, 
                    porta_consultada, 
                    motivo, 
                    protocolo_judicial,
                    ip_privado,
                    cliente_nome,
                    ipv6_cliente,
                    log_data_hora,
                    log_acao,
                    log_destino,
                    log_protocolo,
                    resultado_registros,
                    ip_origem_consulta,
                    user_agent
                ) VALUES (?, ?::inet, ?, ?, ?, ?::inet, ?, ?::inet, ?, ?, ?, ?, ?, ?::inet, ?)
            ");
            $stmt->execute([
                $_SESSION['usuario'],
                $ip_consultado,
                $porta_sql,
                $motivo,
                $protocolo,
                $ip_privado_sql,
                $cliente_nome ?: 'Nao identificado',
                $ipv6_prefix_sql,
                $log_data_hora_sql,
                $log_acao_sql,
                $log_destino_sql,
                $log_protocolo_sql,
                $total,
                $ip_origem,
                $_SERVER['HTTP_USER_AGENT'] ?? null
            ]);
            
            if (empty($mensagem)) {
                $mensagem = $total > 0 ? "✅ Encontrados {$total} registros." : '⚠️ Nenhum registro encontrado.';
            }
            
        } catch (Exception $e) {
            $mensagem = "❌ Erro: " . $e->getMessage();
        }
    }
}

include 'menu.php';
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Consulta CGNAT - LGPD</title>
    <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
    <meta http-equiv="Pragma" content="no-cache">
    <meta http-equiv="Expires" content="0">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; padding: 20px; }
        .container { max-width: 1300px; margin: 0 auto; background: white; border-radius: 10px; padding: 30px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #667eea; padding-bottom: 15px; margin-bottom: 25px; }
        .row { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
        .form-group { margin-bottom: 20px; }
        label { display: block; font-weight: 600; margin-bottom: 5px; color: #555; }
        input, select { width: 100%; padding: 12px; border: 2px solid #e0e0e0; border-radius: 8px; font-size: 14px; }
        input:focus, select:focus { border-color: #667eea; outline: none; }
        .btn { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border: none; padding: 15px 40px; border-radius: 8px; font-size: 16px; font-weight: 600; cursor: pointer; }
        .btn:hover { opacity: 0.9; transform: translateY(-2px); }
        .btn-danger { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); }
        .results { margin-top: 30px; border-top: 2px solid #eee; padding-top: 20px; overflow-x: auto; }
        table { width: 100%; border-collapse: collapse; font-size: 14px; }
        th { background: #f8f9fa; padding: 12px; text-align: left; border-bottom: 2px solid #dee2e6; white-space: nowrap; }
        td { padding: 10px; border-bottom: 1px solid #eee; vertical-align: middle; }
        tr:hover { background: #f8f9fa; }
        .badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 12px; font-weight: 600; }
        .badge-success { background: #d4edda; color: #155724; }
        .badge-danger { background: #f8d7da; color: #721c24; }
        .badge-info { background: #cce5ff; color: #004085; }
        .badge-warning { background: #fff3cd; color: #856404; }
        .badge-cgnat { background: #fff3e0; color: #e65100; }
        .badge-publico { background: #e3f2fd; color: #0d47a1; }
        .badge-privado { background: #f3e5f5; color: #4a148c; }
        .badge-loopback { background: #fce4ec; color: #880e4f; }
        .badge-linklocal { background: #e0f7fa; color: #006064; }
        .badge-ipv6 { background: #d1ecf1; color: #0c5460; padding: 3px 10px; border-radius: 20px; font-size: 12px; font-weight: 600; display: inline-block; font-family: monospace; }
        .badge-cliente { background: #e8f5e9; color: #2e7d32; padding: 6px 16px; border-radius: 20px; font-size: 15px; font-weight: 700; display: inline-block; }
        .badge-nao-identificado { background: #fce4ec; color: #c62828; padding: 6px 16px; border-radius: 20px; font-size: 15px; font-weight: 700; display: inline-block; }
        .alert { padding: 15px; border-radius: 8px; margin-bottom: 20px; }
        .alert-success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .alert-danger { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .alert-warning { background: #fff3cd; color: #856404; border: 1px solid #ffeeba; }
        .alert-info { background: #cce5ff; color: #004085; border: 1px solid #b8d4f0; }
        .client-info { 
            background: linear-gradient(135deg, #e8f5e9 0%, #c8e6c9 100%);
            padding: 20px; 
            border-radius: 12px; 
            margin: 15px 0; 
            border-left: 6px solid #2e7d32;
            box-shadow: 0 2px 8px rgba(0,0,0,0.08);
        }
        .client-info h3 { color: #1b5e20; margin: 0; font-size: 20px; }
        .client-info p { margin-top: 8px; color: #2e7d32; font-size: 15px; }
        .client-info .destaque { font-weight: 700; color: #1b5e20; }
        .client-info .label-info { 
            display: inline-block; 
            background: rgba(255,255,255,0.6); 
            padding: 2px 10px; 
            border-radius: 4px; 
            font-size: 12px;
            color: #1b5e20;
        }
        .client-info .ip-badge {
            display: inline-block;
            padding: 2px 10px;
            border-radius: 4px;
            font-size: 12px;
            font-weight: 600;
        }
        .text-muted { color: #999; }
        .info-required { font-size: 12px; color: #888; margin-top: 5px; }
        .divisor { border-top: 2px dashed #dee2e6; margin: 20px 0; }
        .tipo-consulta { 
            display: inline-block; 
            padding: 4px 12px; 
            border-radius: 20px; 
            font-size: 12px; 
            font-weight: 600;
            background: #e3f2fd;
            color: #0d47a1;
        }
        .cliente-encontrado { 
            display: inline-block; 
            padding: 4px 12px; 
            border-radius: 20px; 
            font-size: 12px; 
            font-weight: 600;
            background: #e8f5e9;
            color: #1b5e20;
        }
        .cliente-nao-encontrado { 
            display: inline-block; 
            padding: 4px 12px; 
            border-radius: 20px; 
            font-size: 12px; 
            font-weight: 600;
            background: #fce4ec;
            color: #c62828;
        }
        @media (max-width: 768px) { 
            .row { grid-template-columns: 1fr; }
            table { font-size: 12px; }
            th, td { padding: 6px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 Consulta CGNAT - LGPD</h1>
        
        <?php if ($mensagem): ?>
        <div class="alert alert-<?php 
            echo strpos($mensagem, 'Nenhum') !== false ? 'warning' : 
                 (strpos($mensagem, 'Erro') !== false ? 'danger' : 
                 (strpos($mensagem, 'identificado') !== false ? 'success' : 'info')); 
        ?>">
            <?php echo $mensagem; ?>
        </div>
        <?php endif; ?>
        
        <?php if ($cliente_encontrado && $cliente_nome && $cliente_nome != 'Nao identificado' && $cliente_nome != 'NAO IDENTIFICADO - Cliente sem IPv6 no período'): ?>
        <div class="client-info">
            <h3>👤 Cliente Identificado</h3>
            <p>
                <span class="destaque"><?php echo htmlspecialchars($cliente_nome); ?></span>
                <?php if (!empty($cliente_login)): ?>
                <span style="margin-left:20px;">
                    <span class="label-info">🔑 Login</span>
                    <strong><?php echo htmlspecialchars($cliente_login); ?></strong>
                </span>
                <?php endif; ?>
                
                <?php if (!empty($ip_privado) && $tipo_ip_info): ?>
                <span style="margin-left:20px;">
                    <span class="label-info">📡 <?php echo $tipo_ip_info['label']; ?></span>
                    <span class="ip-badge <?php echo $tipo_ip_info['class']; ?>">
                        <strong><?php echo htmlspecialchars($ip_privado); ?></strong>
                    </span>
                </span>
                <?php endif; ?>
                
                <?php if (!empty($ipv6_prefix)): ?>
                <span style="margin-left:20px;">
                    <span class="label-info">🌐 Prefixo IPv6</span>
                    <strong><?php echo htmlspecialchars($ipv6_prefix); ?></strong>
                </span>
                <?php endif; ?>
            </p>
            <p style="font-size:13px;color:#388e3c;margin-top:5px;">
                ✅ Cliente identificado com sucesso via IPv6 (busca independente)
            </p>
        </div>
        <?php endif; ?>
        
        <form method="POST" id="formConsulta">
            <div class="row">
                <div class="form-group">
                    <label>IP Público (IPv4 CGNAT)</label>
                    <input type="text" name="ip_publico" id="ip_publico" placeholder="Ex: 190.196.242.18" value="<?php echo htmlspecialchars($_POST['ip_publico'] ?? ''); ?>">
                    <div class="info-required">Busca logs CGNAT + identifica cliente via MK-AUTH</div>
                </div>
                <div class="form-group">
                    <label>Porta Pública</label>
                    <input type="number" name="porta" id="porta" placeholder="Ex: 51478" value="<?php echo htmlspecialchars($_POST['porta'] ?? ''); ?>">
                    <div class="info-required">Obrigatório se informar IP Público</div>
                </div>
            </div>
            
            <div class="divisor"></div>
            
            <div class="row">
                <div class="form-group">
                    <label>IPv6 do Cliente</label>
                    <input type="text" name="ipv6_busca" id="ipv6_busca" placeholder="Ex: 2804:3b80:5000:cd00:31d2:16c0:eaa4:1266" value="<?php echo htmlspecialchars($_POST['ipv6_busca'] ?? ''); ?>">
                    <div class="info-required">🔴 Busca independente - NÃO depende de CGNAT</div>
                </div>
                <div class="form-group">
                    <label>&nbsp;</label>
                    <div style="background:#e8f5e9;padding:12px;border-radius:8px;border:1px solid #c8e6c9;">
                        <span style="font-size:13px;color:#2e7d32;">
                            ✅ Busca diretamente nos logs usando o prefixo /56
                        </span>
                    </div>
                </div>
            </div>
            
            <div class="divisor"></div>
            
            <div class="row">
                <div class="form-group">
                    <label>Data Início</label>
                    <input type="date" name="data_inicio" id="data_inicio" value="<?php echo htmlspecialchars($_POST['data_inicio'] ?? $data_atual); ?>">
                </div>
                <div class="form-group">
                    <label>Data Fim</label>
                    <input type="date" name="data_fim" id="data_fim" value="<?php echo htmlspecialchars($_POST['data_fim'] ?? $data_atual); ?>">
                </div>
            </div>
            <div class="row">
                <div class="form-group">
                    <label>Hora Início</label>
                    <input type="time" name="hora_inicio" id="hora_inicio" value="<?php echo htmlspecialchars($_POST['hora_inicio'] ?? '00:00'); ?>">
                </div>
                <div class="form-group">
                    <label>Hora Fim</label>
                    <input type="time" name="hora_fim" id="hora_fim" value="<?php echo htmlspecialchars($_POST['hora_fim'] ?? '23:59'); ?>">
                </div>
            </div>
            
            <div class="divisor"></div>
            
            <div class="row">
                <div class="form-group">
                    <label>Motivo da Consulta</label>
                    <input type="text" name="motivo" id="motivo" value="Consulta LGPD">
                </div>
                <div class="form-group">
                    <label>Protocolo Judicial</label>
                    <input type="text" name="protocolo" id="protocolo" placeholder="Número do processo (opcional)">
                </div>
            </div>
            
            <div style="display:flex;gap:10px;flex-wrap:wrap;margin-top:10px;">
                <button type="submit" class="btn">🔍 Consultar</button>
                <button type="button" class="btn btn-danger" onclick="limparFormulario()">↺ Limpar</button>
            </div>
        </form>
        
        <?php if ($resultados && $total > 0): ?>
        <div class="results">
            <h3>
                📋 Resultados (<?php echo $total; ?> registros)
                <span class="tipo-consulta">
                    <?php 
                    if (!empty($ipv6_busca)) {
                        echo '🌐 Busca IPv6 (independente)';
                    } else {
                        echo '📡 Busca CGNAT';
                    }
                    ?>
                </span>
                <?php if ($cliente_encontrado && $cliente_nome != 'NAO IDENTIFICADO - Cliente sem IPv6 no período'): ?>
                <span class="cliente-encontrado">✅ Cliente: <?php echo htmlspecialchars($cliente_nome); ?></span>
                <?php else: ?>
                <span class="cliente-nao-encontrado">❌ Cliente não identificado</span>
                <?php endif; ?>
            </h3>
            
            <table>
                <thead>
                    <tr>
                        <th>Data/Hora</th>
                        <th>Evento</th>
                        <th>IP Privado</th>
                        <th>Porta</th>
                        <th>IP Público</th>
                        <th>Porta Pública</th>
                        <th>Destino</th>
                        <th>Protocolo</th>
                        <th>IPv6</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($resultados as $row): ?>
                    <tr>
                        <td style="white-space:nowrap;">
                            <?php echo date('d/m/Y H:i:s', strtotime($row['data_hora'])); ?>
                        </td>
                        <td>
                            <span class="badge <?php echo $row['acao'] == 'Created' ? 'badge-success' : 'badge-danger'; ?>">
                                <?php echo $row['acao'] == 'Created' ? '📌 Criação' : '❌ Deleção'; ?>
                            </span>
                        </td>
                        <td><?php echo htmlspecialchars($row['ip_privado'] ?? '-'); ?></td>
                        <td><?php echo htmlspecialchars($row['porta_privada'] ?? '-'); ?></td>
                        <td><strong><?php echo htmlspecialchars($row['ip_publico']); ?></strong></td>
                        <td><strong><?php echo htmlspecialchars($row['porta_publica']); ?></strong></td>
                        <td><?php echo htmlspecialchars(($row['ip_destino'] ?? '') . ':' . ($row['porta_destino'] ?? '')); ?></td>
                        <td><?php echo htmlspecialchars($row['protocolo'] ?? '-'); ?></td>
                        <td>
                            <?php if (!empty($row['ipv6_cliente'])): ?>
                                <span class="badge-ipv6"><?php echo htmlspecialchars($row['ipv6_cliente']); ?></span>
                            <?php else: ?>
                                <span class="text-muted">-</span>
                            <?php endif; ?>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
            
            <div style="margin-top:15px;padding:15px;background:#f8f9fa;border-radius:8px;font-size:13px;color:#555;">
                <strong>📌 Resumo da consulta:</strong>
                <?php if (!empty($ipv6_busca)): ?>
                    <span>IPv6 consultado: <code><?php echo htmlspecialchars($ipv6_busca); ?></code></span>
                    <span style="margin-left:15px;">Prefix extraído: <code><?php echo htmlspecialchars($ipv6_prefix ?: $ipv6_normalizado); ?></code></span>
                    <?php if ($cliente_encontrado && $cliente_nome != 'NAO IDENTIFICADO - Cliente sem IPv6 no período'): ?>
                    <span style="margin-left:15px;">Cliente: <strong><?php echo htmlspecialchars($cliente_nome); ?></strong></span>
                    <?php endif; ?>
                <?php else: ?>
                    <span>IP: <code><?php echo htmlspecialchars($ip_publico); ?></code></span>
                    <span style="margin-left:15px;">Porta: <code><?php echo htmlspecialchars($porta); ?></code></span>
                    <span style="margin-left:15px;">Cliente: <strong><?php echo htmlspecialchars($cliente_nome); ?></strong></span>
                <?php endif; ?>
                <span style="margin-left:15px;">Período: <code><?php echo date('d/m/Y H:i', strtotime($data_inicio)); ?></code> até <code><?php echo date('d/m/Y H:i', strtotime($data_fim)); ?></code></span>
            </div>
        </div>
        <?php endif; ?>
    </div>
    
    <script>
    function limparFormulario() {
        var dataAtual = '<?php echo date("Y-m-d"); ?>';
        
        document.getElementById('ip_publico').value = '';
        document.getElementById('porta').value = '';
        document.getElementById('ipv6_busca').value = '';
        document.getElementById('protocolo').value = '';
        
        document.getElementById('data_inicio').value = dataAtual;
        document.getElementById('data_fim').value = dataAtual;
        document.getElementById('hora_inicio').value = '00:00';
        document.getElementById('hora_fim').value = '23:59';
        document.getElementById('motivo').value = 'Consulta LGPD';
        
        var alerts = document.querySelectorAll('.alert');
        alerts.forEach(function(el) { el.style.display = 'none'; });
        
        var clientInfo = document.querySelector('.client-info');
        if (clientInfo) { clientInfo.style.display = 'none'; }
        
        var results = document.querySelector('.results');
        if (results) { results.style.display = 'none'; }
    }
    </script>
</body>
</html>
CONSULTAR_PHP

# 12.11 RELATORIOS.PHP
cat > /var/www/html/cgnat/relatorios.php << 'RELATORIOS_PHP'
<?php
require_once 'auth.php';
verificarPermissao('juridico');
require_once 'functions.php';

$db = getDBConnection();

$data_inicio = $_GET['data_inicio'] ?? date('Y-m-01');
$data_fim = $_GET['data_fim'] ?? date('Y-m-d');

try {
    $stmt = $db->prepare("SELECT COUNT(*) as total, COUNT(DISTINCT usuario) as usuarios, COUNT(DISTINCT ip_consultado) as ips_consultados, MIN(data_consulta) as primeira, MAX(data_consulta) as ultima FROM lgpd_audit WHERE DATE(data_consulta) BETWEEN ? AND ?");
    $stmt->execute([$data_inicio, $data_fim]);
    $resumo = $stmt->fetch(PDO::FETCH_ASSOC);
    
    $stmt = $db->prepare("SELECT usuario, COUNT(*) as total, COUNT(DISTINCT ip_consultado) as ips FROM lgpd_audit WHERE DATE(data_consulta) BETWEEN ? AND ? GROUP BY usuario ORDER BY total DESC");
    $stmt->execute([$data_inicio, $data_fim]);
    $por_usuario = $stmt->fetchAll(PDO::FETCH_ASSOC);
    
    $stmt = $db->prepare("
        SELECT 
            a.id, 
            a.usuario, 
            a.ip_consultado, 
            a.porta_consultada, 
            a.motivo, 
            a.protocolo_judicial, 
            a.data_consulta,
            a.cliente_nome,
            a.ip_privado,
            a.ipv6_cliente
        FROM lgpd_audit a
        WHERE DATE(a.data_consulta) BETWEEN ? AND ? 
        ORDER BY a.data_consulta DESC 
        LIMIT 50
    ");
    $stmt->execute([$data_inicio, $data_fim]);
    $ultimas = $stmt->fetchAll(PDO::FETCH_ASSOC);
} catch (Exception $e) {
    $mensagem_erro = "Erro ao carregar dados: " . $e->getMessage();
}

include 'menu.php';
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Relatórios LGPD</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 10px; padding: 30px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; margin-bottom: 20px; }
        .row { display: grid; grid-template-columns: 1fr 1fr 1fr 1fr; gap: 20px; margin-bottom: 30px; }
        .card { background: #f8f9fa; padding: 15px; border-radius: 8px; text-align: center; }
        .card .numero { font-size: 28px; font-weight: bold; color: #667eea; }
        .card .label { font-size: 14px; color: #888; margin-top: 5px; }
        .filtros { display: flex; gap: 20px; align-items: flex-end; margin-bottom: 20px; flex-wrap: wrap; }
        .filtros input { padding: 8px; border: 1px solid #ddd; border-radius: 5px; }
        .btn { padding: 8px 20px; background: #667eea; color: white; border: none; border-radius: 5px; cursor: pointer; }
        .btn-sm { padding: 4px 12px; font-size: 12px; background: #27ae60; color: white; border: none; border-radius: 4px; cursor: pointer; text-decoration: none; display: inline-block; }
        .btn-sm:hover { opacity: 0.8; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; font-size: 14px; }
        th { background: #f8f9fa; padding: 10px; text-align: left; border-bottom: 2px solid #dee2e6; }
        td { padding: 8px; border-bottom: 1px solid #eee; }
        tr:hover { background: #f8f9fa; }
        .alert { padding: 12px; border-radius: 8px; margin-bottom: 20px; background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .badge-info { background: #cce5ff; color: #004085; padding: 2px 8px; border-radius: 20px; font-size: 12px; font-weight: 600; display: inline-block; }
        .badge-ipv6 { background: #d1ecf1; color: #0c5460; padding: 2px 8px; border-radius: 20px; font-size: 11px; font-weight: 600; display: inline-block; font-family: monospace; }
        .text-muted { color: #999; }
        @media (max-width: 768px) { .row { grid-template-columns: 1fr 1fr; } table { font-size: 12px; } }
    </style>
</head>
<body>
    <div class="container">
        <h1>📊 Relatórios LGPD</h1>
        <?php if (isset($mensagem_erro)): ?><div class="alert">❌ <?php echo $mensagem_erro; ?></div><?php endif; ?>
        
        <form class="filtros" method="GET">
            <div><label>Data Início</label><input type="date" name="data_inicio" value="<?php echo $data_inicio; ?>"></div>
            <div><label>Data Fim</label><input type="date" name="data_fim" value="<?php echo $data_fim; ?>"></div>
            <div><button type="submit" class="btn">Filtrar</button></div>
        </form>
        
        <div class="row">
            <div class="card"><div class="numero"><?php echo $resumo['total'] ?? 0; ?></div><div class="label">Total Consultas</div></div>
            <div class="card"><div class="numero"><?php echo $resumo['usuarios'] ?? 0; ?></div><div class="label">Usuários</div></div>
            <div class="card"><div class="numero"><?php echo $resumo['ips_consultados'] ?? 0; ?></div><div class="label">IPs Consultados</div></div>
            <div class="card"><div class="numero"><?php echo $resumo['primeira'] ? date('d/m/Y', strtotime($resumo['primeira'])) : '-'; ?></div><div class="label">Primeira</div></div>
        </div>
        
        <h3>👤 Consultas por Usuário</h3>
        <table>
            <thead><tr><th>Usuário</th><th>Total</th><th>IPs</th></tr></thead>
            <tbody>
                <?php if ($por_usuario): foreach ($por_usuario as $row): ?>
                <tr><td><?php echo htmlspecialchars($row['usuario']); ?></td><td><?php echo $row['total']; ?></td><td><?php echo $row['ips']; ?></td></tr>
                <?php endforeach; else: ?>
                <tr><td colspan="3" style="text-align:center;color:#999;">Nenhuma consulta</td></tr>
                <?php endif; ?>
            </tbody>
        </table>
        
        <h3 style="margin-top:30px;">📋 Últimas Consultas</h3>
        <table>
            <thead>
                <tr>
                    <th>Data</th>
                    <th>Usuário</th>
                    <th>IP</th>
                    <th>Porta</th>
                    <th>Cliente</th>
                    <th>IPv4</th>
                    <th>IPv6</th>
                    <th>Motivo</th>
                </tr>
            </thead>
            <tbody>
                <?php if ($ultimas): foreach ($ultimas as $row): ?>
                <tr>
                    <td><?php echo date('d/m/Y H:i', strtotime($row['data_consulta'])); ?></td>
                    <td><?php echo htmlspecialchars($row['usuario']); ?></td>
                    <td><strong><?php echo htmlspecialchars($row['ip_consultado'] ?? '-'); ?></strong></td>
                    <td><?php echo htmlspecialchars($row['porta_consultada'] ?? '-'); ?></td>
                    <td>
                        <?php if (!empty($row['cliente_nome'])): ?>
                            <span class="badge-info"><?php echo htmlspecialchars($row['cliente_nome']); ?></span>
                        <?php else: ?>
                            <span class="text-muted">-</span>
                        <?php endif; ?>
                    </td>
                    <td><?php echo htmlspecialchars($row['ip_privado'] ?? '-'); ?></td>
                    <td>
                        <?php if (!empty($row['ipv6_cliente'])): ?>
                            <span class="badge-ipv6"><?php echo htmlspecialchars($row['ipv6_cliente']); ?></span>
                        <?php else: ?>
                            <span class="text-muted">-</span>
                        <?php endif; ?>
                    </td>
                    <td><?php echo htmlspecialchars($row['motivo']); ?></td>
                </tr>
                <?php endforeach; else: ?>
                <tr><td colspan="8" style="text-align:center;color:#999;">Nenhuma consulta</td></tr>
                <?php endif; ?>
            </tbody>
        </table>
    </div>
</body>
</html>
RELATORIOS_PHP

# 12.12 ADMIN.PHP
cat > /var/www/html/cgnat/admin.php << 'ADMIN_PHP'
<?php
require_once 'auth.php';
verificarPermissao('admin');
require_once 'functions.php';

$db = getDBConnection();
$mensagem = ''; $mensagem_tipo = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['acao'])) {
        try {
            switch ($_POST['acao']) {
                case 'novo_usuario':
                    $usuario = $_POST['usuario'] ?? ''; $senha = $_POST['senha'] ?? ''; $nome = $_POST['nome_completo'] ?? ''; $perfil = $_POST['perfil'] ?? 'operador';
                    if ($usuario && $senha) { $hash = password_hash($senha, PASSWORD_DEFAULT); $stmt = $db->prepare("INSERT INTO usuarios (usuario, senha_hash, nome_completo, perfil) VALUES (?, ?, ?, ?)"); $stmt->execute([$usuario, $hash, $nome, $perfil]); $mensagem = "✅ Usuário criado!"; $mensagem_tipo = 'success'; }
                    break;
                case 'alterar_senha':
                    $id = $_POST['id'] ?? 0; $nova_senha = $_POST['nova_senha'] ?? ''; $confirmar = $_POST['confirmar_senha'] ?? '';
                    if ($id && $nova_senha && $confirmar) {
                        if ($nova_senha !== $confirmar) { $mensagem = "❌ Senhas não coincidem!"; $mensagem_tipo = 'danger'; }
                        elseif (strlen($nova_senha) < 6) { $mensagem = "❌ Mínimo 6 caracteres."; $mensagem_tipo = 'danger'; }
                        else { $hash = password_hash($nova_senha, PASSWORD_DEFAULT); $stmt = $db->prepare("UPDATE usuarios SET senha_hash = ? WHERE id = ?"); $stmt->execute([$hash, $id]); $mensagem = "✅ Senha alterada!"; $mensagem_tipo = 'success'; }
                    } else { $mensagem = "❌ Preencha todos os campos."; $mensagem_tipo = 'danger'; }
                    break;
                case 'desativar_usuario':
                    $id = $_POST['id'] ?? 0;
                    if ($id == $_SESSION['user_id']) { $mensagem = "❌ Não pode desativar a si mesmo!"; $mensagem_tipo = 'danger'; }
                    else { $stmt = $db->prepare("UPDATE usuarios SET ativo = false WHERE id = ?"); $stmt->execute([$id]); $mensagem = "✅ Desativado!"; $mensagem_tipo = 'success'; }
                    break;
                case 'ativar_usuario':
                    $id = $_POST['id'] ?? 0;
                    $stmt = $db->prepare("UPDATE usuarios SET ativo = true WHERE id = ?"); $stmt->execute([$id]); $mensagem = "✅ Ativado!"; $mensagem_tipo = 'success';
                    break;
            }
        } catch (Exception $e) { $mensagem = "❌ Erro: " . $e->getMessage(); $mensagem_tipo = 'danger'; }
    }
}

try {
    $stmt = $db->query("SELECT id, usuario, nome_completo, perfil, ativo, ultimo_acesso FROM usuarios ORDER BY id");
    $usuarios = $stmt->fetchAll(PDO::FETCH_ASSOC);
    $stmt = $db->query("SELECT COUNT(*) FROM lgpd_audit"); $total_consultas = $stmt->fetchColumn();
    $stmt = $db->query("SELECT COUNT(*) FROM cgnat_logs"); $total_logs = $stmt->fetchColumn();
    $stmt = $db->query("SELECT COUNT(*) FROM clientes"); $total_clientes = $stmt->fetchColumn();
} catch (Exception $e) { $mensagem = "❌ Erro: " . $e->getMessage(); $mensagem_tipo = 'danger'; $usuarios = []; $total_consultas = 0; $total_logs = 0; $total_clientes = 0; }

include 'menu.php';
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Admin CGNAT</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background: #f5f5f5; padding: 20px; }
        .container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 10px; padding: 30px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; margin-bottom: 20px; }
        .row { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 20px; margin-bottom: 30px; }
        .card { background: #f8f9fa; padding: 15px; border-radius: 8px; text-align: center; }
        .card .numero { font-size: 28px; font-weight: bold; color: #667eea; }
        .card .label { font-size: 14px; color: #888; margin-top: 5px; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: #f8f9fa; padding: 12px; text-align: left; border-bottom: 2px solid #dee2e6; }
        td { padding: 10px; border-bottom: 1px solid #eee; vertical-align: middle; }
        .btn { padding: 6px 12px; border: none; border-radius: 5px; cursor: pointer; font-size: 13px; margin: 2px; display: inline-block; }
        .btn-success { background: #27ae60; color: white; }
        .btn-danger { background: #e74c3c; color: white; }
        .btn-primary { background: #667eea; color: white; }
        .btn-warning { background: #f39c12; color: white; }
        .btn-sm { padding: 4px 8px; font-size: 12px; }
        .form-group { margin-bottom: 15px; }
        .form-group label { display: block; font-weight: 600; margin-bottom: 5px; }
        .form-group input, .form-group select { width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 5px; }
        .row-form { display: grid; grid-template-columns: 1fr 1fr 1fr; gap: 20px; }
        .alert { padding: 12px; border-radius: 8px; margin-bottom: 20px; }
        .alert-success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .alert-danger { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 12px; font-weight: 600; }
        .badge-success { background: #d4edda; color: #155724; }
        .badge-danger { background: #f8d7da; color: #721c24; }
        .badge-warning { background: #fff3cd; color: #856404; }
        .badge-info { background: #cce5ff; color: #004085; }
        .modal { display: none; position: fixed; z-index: 1000; left: 0; top: 0; width: 100%; height: 100%; background-color: rgba(0,0,0,0.5); justify-content: center; align-items: center; }
        .modal-content { background: white; padding: 30px; border-radius: 10px; max-width: 400px; width: 90%; box-shadow: 0 4px 20px rgba(0,0,0,0.3); }
        .modal-content h3 { margin-bottom: 20px; }
        .modal-content .form-group { margin-bottom: 15px; }
        .modal-content .btn { width: 100%; }
        .modal-close { float: right; background: none; border: none; font-size: 24px; cursor: pointer; color: #888; }
        .modal-close:hover { color: #333; }
        @media (max-width: 768px) { .row { grid-template-columns: 1fr; } .row-form { grid-template-columns: 1fr; } }
    </style>
</head>
<body>
    <div class="container">
        <h1>⚙️ Administração</h1>
        <?php if ($mensagem): ?>
        <div class="alert alert-<?php echo $mensagem_tipo == 'danger' ? 'danger' : 'success'; ?>"><?php echo $mensagem; ?></div>
        <?php endif; ?>
        <div class="row">
            <div class="card"><div class="numero"><?php echo count($usuarios); ?></div><div class="label">Usuários</div></div>
            <div class="card"><div class="numero"><?php echo number_format($total_logs); ?></div><div class="label">Logs CGNAT</div></div>
            <div class="card"><div class="numero"><?php echo number_format($total_clientes); ?></div><div class="label">Clientes</div></div>
        </div>
        <h3>👤 Usuários</h3>
        <table>
            <thead><tr><th>Usuário</th><th>Nome</th><th>Perfil</th><th>Status</th><th>Último Acesso</th><th>Ações</th></tr></thead>
            <tbody>
                <?php if ($usuarios): foreach ($usuarios as $user): $is_admin = ($user['usuario'] == 'admin'); ?>
                <tr>
                    <td><?php echo htmlspecialchars($user['usuario']); if ($is_admin): ?><span class="badge" style="background:#8e44ad;color:white;">👑</span><?php endif; ?></td>
                    <td><?php echo htmlspecialchars($user['nome_completo'] ?? '-'); ?></td>
                    <td><span class="badge <?php echo $user['perfil'] == 'admin' ? 'badge-danger' : ($user['perfil'] == 'juridico' ? 'badge-warning' : 'badge-info'); ?>"><?php echo $user['perfil']; ?></span></td>
                    <td><span class="badge <?php echo $user['ativo'] ? 'badge-success' : 'badge-danger'; ?>"><?php echo $user['ativo'] ? 'Ativo' : 'Inativo'; ?></span></td>
                    <td><?php echo $user['ultimo_acesso'] ? date('d/m/Y H:i', strtotime($user['ultimo_acesso'])) : 'Nunca'; ?></td>
                    <td>
                        <?php if (!$is_admin): ?>
                            <?php if ($user['ativo']): ?>
                            <form method="POST" style="display:inline;"><input type="hidden" name="acao" value="desativar_usuario"><input type="hidden" name="id" value="<?php echo $user['id']; ?>"><button type="submit" class="btn btn-danger btn-sm">Desativar</button></form>
                            <?php else: ?>
                            <form method="POST" style="display:inline;"><input type="hidden" name="acao" value="ativar_usuario"><input type="hidden" name="id" value="<?php echo $user['id']; ?>"><button type="submit" class="btn btn-success btn-sm">Ativar</button></form>
                            <?php endif; ?>
                        <?php else: ?><span style="color:#888;font-size:12px;">Protegido</span><?php endif; ?>
                        <button class="btn btn-warning btn-sm" onclick="abrirModalAlterarSenha(<?php echo $user['id']; ?>, '<?php echo htmlspecialchars($user['usuario']); ?>')">🔑 Senha</button>
                    </td>
                </tr>
                <?php endforeach; else: ?>
                <tr><td colspan="6" style="text-align:center;color:#999;">Nenhum usuário</td></tr>
                <?php endif; ?>
            </tbody>
        </table>
        <h3 style="margin-top:30px;">➕ Criar Usuário</h3>
        <form method="POST"><input type="hidden" name="acao" value="novo_usuario">
            <div class="row-form">
                <div class="form-group"><label>Usuário *</label><input type="text" name="usuario" required></div>
                <div class="form-group"><label>Senha *</label><input type="text" name="senha" required></div>
                <div class="form-group"><label>Nome</label><input type="text" name="nome_completo"></div>
            </div>
            <div class="form-group" style="max-width:300px;"><label>Perfil</label><select name="perfil"><option value="operador">Operador</option><option value="juridico">Jurídico</option><option value="admin">Administrador</option></select></div>
            <button type="submit" class="btn btn-primary">Criar</button>
        </form>
    </div>
    <div id="modalSenha" class="modal">
        <div class="modal-content">
            <button class="modal-close" onclick="fecharModal()">&times;</button>
            <h3>🔑 Alterar Senha</h3>
            <form method="POST" id="formSenha" onsubmit="return validarSenha()">
                <input type="hidden" name="acao" value="alterar_senha"><input type="hidden" name="id" id="usuario_id">
                <div class="form-group"><label>Usuário</label><input type="text" id="usuario_nome" disabled style="background:#f0f0f0;"></div>
                <div class="form-group"><label>Nova Senha</label><input type="password" name="nova_senha" id="nova_senha" required minlength="6" placeholder="Mínimo 6 caracteres"></div>
                <div class="form-group"><label>Confirmar</label><input type="password" name="confirmar_senha" id="confirmar_senha" required></div>
                <button type="submit" class="btn btn-primary">Salvar</button>
            </form>
        </div>
    </div>
    <script>
        function abrirModalAlterarSenha(id, usuario) {
            document.getElementById('modalSenha').style.display = 'flex';
            document.getElementById('usuario_id').value = id;
            document.getElementById('usuario_nome').value = usuario;
            document.getElementById('nova_senha').value = '';
            document.getElementById('confirmar_senha').value = '';
        }
        function fecharModal() { document.getElementById('modalSenha').style.display = 'none'; }
        function validarSenha() {
            var nova = document.getElementById('nova_senha').value;
            var confirmar = document.getElementById('confirmar_senha').value;
            if (nova.length < 6) { alert('Mínimo 6 caracteres.'); return false; }
            if (nova !== confirmar) { alert('Senhas não coincidem.'); return false; }
            return confirm('Alterar senha?');
        }
        window.onclick = function(event) { if (event.target == document.getElementById('modalSenha')) fecharModal(); }
    </script>
</body>
</html>
ADMIN_PHP

print_success "TODOS os arquivos PHP criados com sucesso!"

# ============================================================
# 13. CONFIGURAR RSYSLOG (CORRIGIDO - SEM IMUDPServerTimeStamp)
# ============================================================
print_header "13. CONFIGURANDO RSYSLOG"

# Criar pipe
mkfifo /var/run/cgnat.pipe 2>/dev/null || true
chmod 666 /var/run/cgnat.pipe 2>/dev/null || true

# ============================================================
# CORREÇÃO: Removido IMUDPServerTimeStamp (não existe mais)
# ============================================================
cat > /etc/rsyslog.d/99-cgnat.conf << 'RSYSLOG'
$MaxMessageSize 64k
$MainMsgQueueSize 5000
$MainMsgQueueDiscardMark 4500
$MainMsgQueueDiscardSeverity 5

module(load="imudp")
input(type="imudp" port="514")

template(name="nat-template" type="string" string="%msg%\n")

if $msg contains 'NAT-6-LOG_TRANSLATION' then {
    action(type="omfile" file="/var/log/cgnat/raw.log" template="nat-template")
    action(type="ompipe" pipe="/var/run/cgnat.pipe" template="nat-template")
    stop
}
RSYSLOG

# Remover qualquer diretório /dev/shm/cgnat_logs
rm -rf /dev/shm/cgnat_logs 2>/dev/null

# Desabilitar serviço de RAM disk
systemctl disable cgnat-ramdisk.service 2>/dev/null || true
systemctl stop cgnat-ramdisk.service 2>/dev/null || true
rm -f /etc/systemd/system/cgnat-ramdisk.service 2>/dev/null

# Configurar logrotate
cat > /etc/logrotate.d/cgnat << 'EOF'
/var/log/cgnat/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 640 syslog adm
    sharedscripts
    postrotate
        systemctl reload rsyslog >/dev/null 2>&1 || true
    endscript
}
EOF

# Criar raw.log com permissões corretas
touch /var/log/cgnat/raw.log
if getent group adm >/dev/null 2>&1; then
    chown syslog:adm /var/log/cgnat/raw.log 2>/dev/null || chown root:adm /var/log/cgnat/raw.log
else
    chown syslog:syslog /var/log/cgnat/raw.log 2>/dev/null || chown root:root /var/log/cgnat/raw.log
fi
chmod 640 /var/log/cgnat/raw.log

# Reiniciar rsyslog
systemctl restart rsyslog 2>/dev/null || true

# Verificar se o rsyslog está rodando sem erros
sleep 2
if systemctl is-active --quiet rsyslog; then
    print_success "Rsyslog configurado (raw.log no DISCO)"
else
    print_warning "Rsyslog não está rodando. Verifique: systemctl status rsyslog"
fi

# ============================================================
# 14. CONFIGURAR CRONJOBS
# ============================================================
print_header "14. CONFIGURANDO CRONJOBS"

cat > /tmp/crontab_cgnat << 'CRON'
0 2 * * * /usr/local/bin/backup_cgnat.sh >> /var/log/cgnat/backup.log 2>&1
*/2 * * * * /usr/local/bin/sync_mkauth.sh >> /var/log/cgnat/sync_mkauth.log 2>&1
25 0 25 * * /usr/local/bin/create_cgnat_partition.sh >> /var/log/cgnat/partition_create.log 2>&1
0 8 * * * /usr/local/bin/monitor_disco.sh >> /var/log/cgnat/disco.log 2>&1
*/5 * * * * /usr/local/bin/clean_shm.sh >> /var/log/cgnat/shm_clean.log 2>&1
*/5 * * * * /usr/local/bin/sync_ipv6_cisco.sh >> /var/log/cgnat/sync_ipv6.log 2>&1
0 */6 * * * /usr/local/bin/check_space.sh"
0 8 * * * /usr/local/bin/check_space.sh --resumo
CRON

crontab /tmp/crontab_cgnat 2>/dev/null || true
rm /tmp/crontab_cgnat

print_success "Cronjobs configurados"

# ============================================================
# 15. CRIAR SCRIPTS ÚTEIS
# ============================================================
print_header "15. CRIANDO SCRIPTS ÚTEIS"

# Script de Backup
sudo -u postgres psql -d cgnat_logs << 'EOF' 2>/dev/null
CREATE USER backup_user WITH PASSWORD 'Backup@2026' SUPERUSER;
GRANT ALL PRIVILEGES ON DATABASE cgnat_logs TO backup_user;
EOF

cat > /usr/local/bin/backup_cgnat.sh << 'BACKUP'
#!/bin/bash
BACKUP_DIR="/backup/cgnat"
DATE=$(date +%Y%m%d_%H%M%S)
LOG_FILE="/var/log/cgnat/backup.log"

DB_NAME="cgnat_logs"
DB_USER="backup_user"
DB_PASS="Backup@2026"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> $LOG_FILE
}

log "========================================"
log "Iniciando backup..."

mkdir -p $BACKUP_DIR
chmod 755 $BACKUP_DIR

export PGPASSWORD="$DB_PASS"
/usr/bin/pg_dump -h localhost -U $DB_USER -d $DB_NAME -Fc -f "$BACKUP_DIR/cgnat_logs_$DATE.dump" 2>> $LOG_FILE
unset PGPASSWORD

if [ -f "$BACKUP_DIR/cgnat_logs_$DATE.dump" ]; then
    TAMANHO=$(stat -c%s "$BACKUP_DIR/cgnat_logs_$DATE.dump")
    if [ $TAMANHO -gt 1024 ]; then
        log "✅ Dump válido criado: $(du -h "$BACKUP_DIR/cgnat_logs_$DATE.dump" | cut -f1)"
        gzip -f "$BACKUP_DIR/cgnat_logs_$DATE.dump"
        if [ -f "$BACKUP_DIR/cgnat_logs_$DATE.dump.gz" ]; then
            log "✅ Backup concluído: $BACKUP_DIR/cgnat_logs_$DATE.dump.gz"
        else
            log "❌ Falha ao compactar o backup"
        fi
    else
        log "❌ Dump vazio ($TAMANHO bytes)"
        rm -f "$BACKUP_DIR/cgnat_logs_$DATE.dump"
    fi
else
    log "❌ Falha ao criar o dump"
fi

find $BACKUP_DIR -name "*.dump.gz" -mtime +30 -delete

log "Backups disponíveis:"
ls -lh $BACKUP_DIR/*.dump.gz 2>/dev/null | while read line; do
    log "  $line"
done

log "Backup finalizado"
BACKUP
chmod +x /usr/local/bin/backup_cgnat.sh

# Script de Monitoramento de Disco
cat > /usr/local/bin/monitor_disco.sh << 'MONITOR'
#!/bin/bash
echo "=== MONITORAMENTO DE DISCO CGNAT ==="
echo "Data: $(date)"
echo ""
echo "📊 Tamanho do banco:"
sudo -u postgres psql -d cgnat_logs -c "SELECT pg_size_pretty(pg_database_size('cgnat_logs')) as tamanho;" 2>/dev/null || echo "Erro ao consultar banco"
echo ""
echo "💾 Espaço em disco:"
df -h /
echo ""
echo "📁 Backups:"
du -sh /backup/cgnat/ 2>/dev/null || echo "Nenhum backup"
echo ""
echo "📁 /dev/shm:"
df -h /dev/shm
MONITOR
chmod +x /usr/local/bin/monitor_disco.sh

# Script para criar partições
cat > /usr/local/bin/create_cgnat_partition.sh << 'PART'
#!/bin/bash
echo "$(date): Criando partições CGNAT..."

sudo -u postgres psql -d cgnat_logs << 'SQL'
DO $$
DECLARE
    mes_atual DATE;
    mes_seguinte DATE;
    nome_particao TEXT;
    data_inicio TEXT;
    data_fim TEXT;
    i INTEGER;
BEGIN
    FOR i IN 0..5 LOOP
        mes_atual := date_trunc('month', CURRENT_DATE + (i || ' months')::INTERVAL);
        mes_seguinte := mes_atual + INTERVAL '1 month';
        data_inicio := to_char(mes_atual, 'YYYY-MM-DD');
        data_fim := to_char(mes_seguinte, 'YYYY-MM-DD');
        nome_particao := 'cgnat_logs_' || to_char(mes_atual, 'YYYY_MM');
        
        IF NOT EXISTS (SELECT 1 FROM pg_tables WHERE tablename = nome_particao) THEN
            EXECUTE format('CREATE TABLE %I PARTITION OF cgnat_logs FOR VALUES FROM (%L) TO (%L)', nome_particao, data_inicio, data_fim);
            EXECUTE format('CREATE INDEX %I ON %I(ip_publico)', 'idx_' || nome_particao || '_ip_pub', nome_particao);
            EXECUTE format('CREATE INDEX %I ON %I(ip_privado)', 'idx_' || nome_particao || '_ip_priv', nome_particao);
            EXECUTE format('CREATE INDEX %I ON %I(data_hora)', 'idx_' || nome_particao || '_data', nome_particao);
            RAISE NOTICE 'Partição % criada', nome_particao;
        END IF;
    END LOOP;
END $$;
SQL

echo "$(date): Partições criadas."
PART
chmod +x /usr/local/bin/create_cgnat_partition.sh

# Script de Sincronização MK-AUTH
print_header "15.5. CRIANDO SCRIPT DE SINCRONIZAÇÃO MK-AUTH"

cat > /usr/local/bin/sync_mkauth.sh << EOF
#!/bin/bash
# Script para sincronizar dados do MK-AUTH via SSH
# NUNCA DELETA clientes - apenas marca como inativo

echo "\$(date): Iniciando sincronização com MK-AUTH..."

# Usando as variáveis do script principal
MK_AUTH_IP="${MK_AUTH_IP}"
MK_AUTH_USER="${MK_AUTH_USER}"
MK_AUTH_PASS="${MK_AUTH_PASS}"
DB_USER="root"
DB_PASS="${MK_AUTH_DB_PASS}"
DB_NAME="mkradius"

TMP_FILE="/tmp/radacct_export_\$\$.csv"

echo "Conectando a \${MK_AUTH_IP}..."

sshpass -p "\${MK_AUTH_PASS}" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR \${MK_AUTH_USER}@\${MK_AUTH_IP} \
"mysql -u \${DB_USER} -p\${DB_PASS} -B -N -e '
SELECT 
    login,
    nome,
    ip
FROM \${DB_NAME}.sis_cliente
WHERE cli_ativado = \"s\"
AND ip IS NOT NULL
AND ip != \"\"
UNION
SELECT 
    username,
    nome,
    ip
FROM \${DB_NAME}.sis_adicional
WHERE bloqueado = \"nao\"
AND ip IS NOT NULL
AND ip != \"\"
'" > "\${TMP_FILE}"

if [ -s "\${TMP_FILE}" ]; then
    CLIENTES=\$(wc -l < "\${TMP_FILE}")
    echo "Dados exportados do MK-AUTH: \${CLIENTES} clientes"
    
    sudo -u postgres psql -d cgnat_logs << SQL
    -- Criar tabela temporária com os dados novos
    CREATE TEMP TABLE temp_clientes (
        login text,
        nome text,
        ip_privado text
    );
    
    COPY temp_clientes (login, nome, ip_privado)
    FROM '\${TMP_FILE}'
    DELIMITER E'\t'
    CSV;
    
    -- Adicionar colunas se não existirem
    ALTER TABLE clientes ADD COLUMN IF NOT EXISTS ativo BOOLEAN DEFAULT TRUE;
    ALTER TABLE clientes ADD COLUMN IF NOT EXISTS data_inativacao TIMESTAMP;
    
    -- Atualizar apenas os campos que vêm do MK-AUTH
    UPDATE clientes c
    SET 
        nome = t.nome,
        ip_privado = t.ip_privado::inet,
        ativo = true,
        data_inativacao = NULL
    FROM temp_clientes t
    WHERE c.login = t.login;
    
    -- Inserir novos clientes (que não existem)
    INSERT INTO clientes (login, nome, ip_privado, ativo)
    SELECT 
        t.login,
        t.nome,
        t.ip_privado::inet,
        true
    FROM temp_clientes t
    LEFT JOIN clientes c ON t.login = c.login
    WHERE c.login IS NULL;
    
    -- Marcar como inativo
    UPDATE clientes 
    SET ativo = false, 
        data_inativacao = NOW()
    WHERE login NOT IN (SELECT login FROM temp_clientes)
    AND ativo = true;
    
    SELECT 'Clientes ativos: ' || COUNT(*) FILTER (WHERE ativo = true) as ativos,
           'Clientes inativos: ' || COUNT(*) FILTER (WHERE ativo = false) as inativos
    FROM clientes;
SQL
    
    rm -f "\${TMP_FILE}"
else
    echo "ERRO: Não foi possível exportar dados do MK-AUTH"
fi

echo "\$(date): Sincronização MK-AUTH concluída."
EOF

chmod +x /usr/local/bin/sync_mkauth.sh
print_success "Script de sincronização MK-AUTH criado"

# Script de Sincronização IPv6 Cisco
print_header "CRIANDO SCRIPT DE SINCRONIZAÇÃO IPv6"

cat > /usr/local/bin/sync_ipv6_cisco.sh << EOF
#!/bin/bash
# Script para sincronizar IPv6 do Cisco ASR com a tabela historico_ipv6

echo "\$(date): Iniciando sincronização IPv6 do Cisco..."
echo "⏳ Aguarde, estamos sincronizando os dados com o Cisco..."

CISCO_IP="${CISCO_IP}"
CISCO_USER="${CISCO_USER}"
CISCO_PASS="${CISCO_PASS}"
TMP_FILE="/tmp/ipv6_binding_\$\$.txt"

# Coletar dados do Cisco
sshpass -p "\$CISCO_PASS" ssh \\
    -o KexAlgorithms=+diffie-hellman-group14-sha1 \\
    -o HostKeyAlgorithms=+ssh-rsa \\
    -o PubkeyAcceptedAlgorithms=+ssh-rsa \\
    -o StrictHostKeyChecking=no \\
    "\$CISCO_USER@\$CISCO_IP" "show ipv6 dhcp binding | include Username|Prefix:" > "\$TMP_FILE" 2>/dev/null

if [ ! -s "\$TMP_FILE" ]; then
    echo "❌ ERRO: Não foi possível coletar dados do Cisco"
    echo "Verifique:"
    echo "  - O Cisco ASR está acessível em \$CISCO_IP?"
    echo "  - As credenciais estão corretas?"
    echo "  - O comando 'show ipv6 dhcp binding' funciona?"
    rm -f "\$TMP_FILE"
    exit 1
fi

echo "📡 Dados coletados, processando..."

UPDATED=0
login=""
prefix=""

while IFS= read -r line; do
    line=\$(echo "\$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//' | tr -d '\r')
    
    if echo "\$line" | grep -q "^Username :"; then
        login=\$(echo "\$line" | sed 's/^Username : //' | tr -d '\r')
    fi
    
    if echo "\$line" | grep -q "^Prefix:"; then
        prefix=\$(echo "\$line" | sed 's/^Prefix: //' | awk '{print \$1}' | tr -d '\r')
        
        if [ ! -z "\$login" ] && [ ! -z "\$prefix" ]; then
            # INSERIR HISTÓRICO em vez de atualizar
            sudo -u postgres psql -d cgnat_logs -q << PSQL 2>/dev/null
-- 1. Fechar registros anteriores do mesmo login (se mudou de prefixo)
UPDATE historico_ipv6 
SET data_fim = NOW(), 
    ativo = false,
    atualizado_em = NOW()
WHERE login = '\$login' 
AND ativo = true 
AND ipv6_prefix != '\$prefix';

-- 2. Verificar se já existe um registro ativo com este prefixo
INSERT INTO historico_ipv6 (login, ipv6_prefix, data_inicio, ativo)
SELECT '\$login', '\$prefix', NOW(), true
WHERE NOT EXISTS (
    SELECT 1 FROM historico_ipv6 
    WHERE login = '\$login' 
    AND ipv6_prefix = '\$prefix' 
    AND ativo = true
);

-- 3. Atualizar a tabela clientes (dados atuais para consulta rápida)
UPDATE clientes 
SET ipv6_prefix = '\$prefix',
    ipv6_atualizado = NOW()
WHERE login = '\$login';
PSQL
            if [ \$? -eq 0 ]; then
                UPDATED=\$((UPDATED + 1))
                # ============================================================
                # LINHA REMOVIDA: NÃO EXIBE MAIS OS CLIENTES
                # echo "  ✅ $login -> $prefix"
                # ============================================================
            fi
        fi
    fi
done < "\$TMP_FILE"

echo "✅ Sincronização IPv6 concluída. Clientes atualizados: \$UPDATED"
echo "📊 Total de clientes com IPv6:"
sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(DISTINCT login) FROM historico_ipv6 WHERE ativo = true;" 2>/dev/null | xargs

rm -f "\$TMP_FILE"
EOF

chmod +x /usr/local/bin/sync_ipv6_cisco.sh
print_success "Script de sincronização IPv6 com histórico criado"

# ============================================================
# 15.8. SCRIPT DE RECUPERAÇÃO DO PARSER
# ============================================================
print_header "15.8. CRIANDO SCRIPT DE RECUPERAÇÃO DO PARSER"

cat > /usr/local/bin/recuperar_parser.sh << 'EOF'
#!/bin/bash
# ============================================================
# RECUPERAÇÃO DO PARSER CGNAT APÓS QUEDA
# ============================================================

echo "========================================"
echo "  🔧 RECUPERANDO PARSER CGNAT"
echo "  Data: $(date)"
echo "========================================"

# 1. Parar serviços
echo "1. Parando serviços..."
systemctl stop cgnat-parser 2>/dev/null
systemctl stop rsyslog 2>/dev/null

# 2. Remover pipe antigo e recriar
echo "2. Recriando pipe..."
rm -f /var/run/cgnat.pipe
mkfifo /var/run/cgnat.pipe
chmod 666 /var/run/cgnat.pipe

# 3. Verificar pipe
ls -la /var/run/cgnat.pipe

# 4. Iniciar rsyslog
echo "3. Iniciando rsyslog..."
systemctl start rsyslog
sleep 2

# 5. Iniciar parser
echo "4. Iniciando parser..."
systemctl start cgnat-parser
sleep 3

# 6. Verificar status
echo ""
echo "5. Status:"
systemctl status cgnat-parser --no-pager | head -10

# 7. Verificar logs
echo ""
echo "6. Últimos logs do parser:"
tail -5 /var/log/cgnat/parser.log 2>/dev/null || echo "  (sem logs)"

echo ""
echo "========================================"
echo "  ✅ Recuperação concluída!"
echo "========================================"
EOF

chmod +x /usr/local/bin/recuperar_parser.sh
print_success "Script de recuperação do parser criado"

# ============================================================
# 15.9. SCRIPT DE RECUPERAÇÃO DO POSTGRESQL
# ============================================================
print_header "15.9. CRIANDO SCRIPT DE RECUPERAÇÃO DO POSTGRESQL"

cat > /usr/local/bin/recuperar_postgres.sh << 'EOF'
#!/bin/bash
# ============================================================
# RECUPERAÇÃO DO POSTGRESQL APÓS QUEDA DE ENERGIA
# ============================================================

echo "========================================"
echo "  🔧 RECUPERANDO POSTGRESQL CGNAT"
echo "  Data: $(date)"
echo "========================================"

# 1. Parar serviços
echo "1. Parando serviços..."
systemctl stop cgnat-parser 2>/dev/null
systemctl stop postgresql@15-main 2>/dev/null
systemctl stop postgresql@17-main 2>/dev/null

# 2. Verificar clusters
echo "2. Verificando clusters..."
pg_lsclusters

# 3. Remover cluster 17 se existir (Debian 13)
if pg_lsclusters 2>/dev/null | grep -q "17.*online"; then
    echo "3. Removendo cluster PostgreSQL 17..."
    pg_dropcluster 17 main --stop 2>/dev/null
fi

# 4. Verificar porta 5432
echo "4. Verificando porta 5432..."
if ss -tlnp 2>/dev/null | grep -q ":5432"; then
    echo "  ⚠️ Porta 5432 ocupada. Matando processo..."
    fuser -k 5432/tcp 2>/dev/null
    sleep 2
fi

# 5. Tentar iniciar PostgreSQL 15
echo "5. Iniciando PostgreSQL 15..."
pg_ctlcluster 15 main start --force 2>/dev/null

if [ $? -eq 0 ]; then
    echo "  ✅ Cluster 15 iniciado com sucesso!"
else
    echo "  ⚠️ Falha na recuperação. Resetando WAL..."
    pg_resetwal -f /var/lib/postgresql/15/main 2>/dev/null
    
    echo "  🔄 Iniciando cluster..."
    pg_ctlcluster 15 main start 2>/dev/null
fi

sleep 3

# 6. Verificar resultado
echo ""
echo "6. Status final:"
pg_lsclusters

if pg_lsclusters 2>/dev/null | grep -q "15.*online"; then
    echo ""
    echo "  ✅ PostgreSQL 15 rodando com sucesso!"
    
    # Recriar usuários se necessário
    echo ""
    echo "7. Verificando usuários..."
    sudo -u postgres psql -c "SELECT 1 FROM pg_user WHERE usename='cgnat_admin';" 2>/dev/null | grep -q 1 || {
        echo "  🔄 Recriando usuários..."
        sudo -u postgres psql -c "CREATE USER cgnat_parser WITH PASSWORD 'Wbt@07717125';" 2>/dev/null
        sudo -u postgres psql -c "CREATE USER cgnat_admin WITH PASSWORD 'Wbt@07717125';" 2>/dev/null
        sudo -u postgres psql -c "CREATE DATABASE cgnat_logs OWNER cgnat_parser;" 2>/dev/null
        sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE cgnat_logs TO cgnat_parser;" 2>/dev/null
        sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE cgnat_logs TO cgnat_admin;" 2>/dev/null
    }
    
    # Reiniciar parser
    /usr/local/bin/recuperar_parser.sh 2>/dev/null || systemctl restart cgnat-parser
    
    echo ""
    echo "  ✅ Recuperação concluída!"
else
    echo ""
    echo "  ❌ Falha ao iniciar PostgreSQL 15"
    echo "  Verifique: sudo tail -50 /var/log/postgresql/postgresql-15-main.log"
fi

echo "========================================"
EOF

chmod +x /usr/local/bin/recuperar_postgres.sh
print_success "Script de recuperação do PostgreSQL criado"

# ============================================================
# 15.10. RECUPERAÇÃO AUTOMÁTICA NO BOOT
# ============================================================
print_header "15.10. CONFIGURANDO RECUPERAÇÃO AUTOMÁTICA NO BOOT"

# Service para recuperar PostgreSQL no boot
cat > /etc/systemd/system/recuperar-postgres-boot.service << 'EOF'
[Unit]
Description=Recuperar PostgreSQL após queda de energia
After=network.target
Before=postgresql.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/recuperar_postgres.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable recuperar-postgres-boot.service

# ============================================================
# 15.11. MONITORAMENTO CONTÍNUO (CRON)
# ============================================================
print_header "15.11. CONFIGURANDO MONITORAMENTO CONTÍNUO"

# Adicionar verificação periódica do parser
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/recuperar_parser.sh >> /var/log/cgnat/recuperar_parser.log 2>&1") | crontab -

# Adicionar verificação do PostgreSQL a cada hora
(crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/recuperar_postgres.sh >> /var/log/cgnat/recuperar_postgres.log 2>&1") | crontab -

print_success "Monitoramento contínuo configurado no cron"

# Service para recuperar parser no boot
cat > /etc/systemd/system/recuperar-parser-boot.service << 'EOF'
[Unit]
Description=Recuperar Parser após queda de energia
After=postgresql.service rsyslog.service
Wants=postgresql.service rsyslog.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/recuperar_parser.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable recuperar-parser-boot.service

print_success "Recuperação automática no boot configurada"

# Script de Monitoramento do /dev/shm
cat > /usr/local/bin/clean_shm.sh << 'EOF'
#!/bin/bash
USO=$(df -h /dev/shm | grep -v Filesystem | awk '{print $5}' | sed 's/%//')

if [ $USO -gt 90 ]; then
    echo "$(date): /dev/shm com $USO% de uso - limpando..." >> /var/log/cgnat/shm_clean.log
    rm -rf /dev/shm/PostgreSQL.* 2>/dev/null
    rm -rf /dev/shm/sem.* 2>/dev/null
    systemctl restart postgresql@15-main 2>/dev/null || true
fi
EOF
chmod +x /usr/local/bin/clean_shm.sh

print_success "Scripts criados com sucesso!"

# Script de Monitoramento da saúde do programa
cat > /usr/local/bin/monitor_cgnat.sh << 'EOF'
#!/bin/bash
# ============================================================
# MONITORAMENTO DEFINITIVO - CGNAT LGPD (VERSÃO FINAL)
# ============================================================

# Cores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Funções de ajuda
show_help() {
    echo "============================================================"
    echo "  📊 MONITORAMENTO CGNAT - Comandos"
    echo "============================================================"
    echo ""
    echo "  ${GREEN}monitor_cgnat.sh${NC}        - Mostra dashboard completo"
    echo "  ${GREEN}monitor_cgnat.sh -l${NC}     - Logs em tempo real (tail -f)"
    echo "  ${GREEN}monitor_cgnat.sh -d${NC}     - Dashboard interativo (atualiza a cada 5s)"
    echo "  ${GREEN}monitor_cgnat.sh -c${NC}     - Diagnóstico rápido"
    echo "  ${GREEN}monitor_cgnat.sh -h${NC}     - Esta ajuda"
    echo ""
    echo "============================================================"
}

# Função para obter espaço em disco de forma robusta
get_disk_info() {
    local mount_point="$1"
    local info=$(df -h "$mount_point" | tail -1)
    local usado=$(echo "$info" | awk '{print $3}')
    local total=$(echo "$info" | awk '{print $2}')
    local percent=$(echo "$info" | awk '{print $5}' | sed 's/%//')
    echo "$usado|$total|$percent"
}

# Função: Dashboard
show_dashboard() {
    clear
    echo "============================================================"
    echo "   📊 DASHBOARD CGNAT - $(date '+%d/%m/%Y %H:%M:%S')"
    echo "============================================================"
    echo ""

    # 1. Serviços
    echo -e "${CYAN}🔹 SERVIÇOS:${NC}"
    for svc in postgresql@15-main rsyslog cgnat-parser apache2; do
        if systemctl is-active --quiet $svc 2>/dev/null; then
            echo -e "  ${GREEN}✅${NC} $svc: rodando"
        else
            echo -e "  ${RED}❌${NC} $svc: PARADO!"
        fi
    done
    echo ""

    # 2. Coleta de Logs
    echo -e "${CYAN}🔹 COLETA DE LOGS:${NC}"
    TOTAL=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM cgnat_logs;" 2>/dev/null | xargs)
    HOJE=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM cgnat_logs WHERE DATE(data_hora) = CURRENT_DATE;" 2>/dev/null | xargs)
    ULTIMO_5MIN=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM cgnat_logs WHERE data_hora > NOW() - INTERVAL '5 minutes';" 2>/dev/null | xargs)
    ULTIMO_LOG=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT MAX(data_hora) FROM cgnat_logs;" 2>/dev/null | xargs)
    
    echo -e "  ${MAGENTA}📊${NC} Total de logs: ${BOLD}${TOTAL:-0}${NC}"
    echo -e "  ${MAGENTA}📊${NC} Logs hoje: ${BOLD}${HOJE:-0}${NC}"
    echo -e "  ${MAGENTA}📊${NC} Últimos 5 min: ${BOLD}${ULTIMO_5MIN:-0}${NC}"
    [ ! -z "$ULTIMO_LOG" ] && echo -e "  ${MAGENTA}🕐${NC} Último log: ${ULTIMO_LOG}"
    echo ""

    # 3. Espaço
    echo -e "${CYAN}🔹 ESPAÇO:${NC}"
    
    DISCO_INFO=$(get_disk_info "/")
    DISCO_USADO=$(echo "$DISCO_INFO" | cut -d'|' -f1)
    DISCO_TOTAL=$(echo "$DISCO_INFO" | cut -d'|' -f2)
    DISCO_PERC=$(echo "$DISCO_INFO" | cut -d'|' -f3)
    
    SHM_INFO=$(get_disk_info "/dev/shm")
    SHM_USADO=$(echo "$SHM_INFO" | cut -d'|' -f1)
    SHM_TOTAL=$(echo "$SHM_INFO" | cut -d'|' -f2)
    SHM_PERC=$(echo "$SHM_INFO" | cut -d'|' -f3)
    
    DB_SIZE=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT pg_size_pretty(pg_database_size('cgnat_logs'));" 2>/dev/null | xargs)
    
    echo -e "  ${MAGENTA}💾${NC} Disco: ${DISCO_USADO} de ${DISCO_TOTAL} (${DISCO_PERC}%)"
    echo -e "  ${MAGENTA}💾${NC} /dev/shm: ${SHM_USADO} de ${SHM_TOTAL} (${SHM_PERC}%)"
    echo -e "  ${MAGENTA}🗄️${NC} Banco: ${DB_SIZE:-N/A}"
    echo ""

    # 4. Autovacuum (CORRIGIDO)
    echo -e "${CYAN}🔹 AUTOVACUUM:${NC}"
    
    # Usar formato CSV para evitar problemas com caracteres especiais
    AUTOVACUUM_DATA=$(sudo -u postgres psql -d cgnat_logs -t -A -F'|' -c "
    SELECT 
        relname,
        n_live_tup,
        n_dead_tup,
        round(n_dead_tup::numeric / NULLIF(n_live_tup, 0) * 100, 2) as perc_mortos
    FROM pg_stat_all_tables 
    WHERE schemaname = 'public' 
    AND relname LIKE 'cgnat_logs%'
    AND n_live_tup > 0
    ORDER BY relname
    LIMIT 1;
    " 2>/dev/null | tr -d ' ')
    
    if [ ! -z "$AUTOVACUUM_DATA" ] && [ "$AUTOVACUUM_DATA" != " " ]; then
        TABELA=$(echo "$AUTOVACUUM_DATA" | cut -d'|' -f1)
        VIVOS=$(echo "$AUTOVACUUM_DATA" | cut -d'|' -f2)
        MORTOS=$(echo "$AUTOVACUUM_DATA" | cut -d'|' -f3)
        PERC=$(echo "$AUTOVACUUM_DATA" | cut -d'|' -f4)
        
        if [ "$PERC" = "0.00" ] || [ -z "$PERC" ]; then
            echo -e "  ${GREEN}✅${NC} ${TABELA}: ${VIVOS} vivos, ${MORTOS} mortos (0%)"
        else
            echo -e "  ${YELLOW}⚠️${NC} ${TABELA}: ${VIVOS} vivos, ${MORTOS} mortos (${PERC}%)"
        fi
    else
        echo -e "  ${YELLOW}⚠️${NC} Aguardando primeira coleta..."
    fi
    echo ""

    # 5. Clientes
    echo -e "${CYAN}🔹 CLIENTES:${NC}"
    TOTAL_CLIENTES=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM clientes;" 2>/dev/null | xargs)
    ATIVOS=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM clientes WHERE ativo = true;" 2>/dev/null | xargs)
    IPV6=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM clientes WHERE ipv6_prefix IS NOT NULL;" 2>/dev/null | xargs)
    echo -e "  ${MAGENTA}👥${NC} Total: ${BOLD}${TOTAL_CLIENTES:-0}${NC}"
    echo -e "  ${MAGENTA}👥${NC} Ativos: ${BOLD}${ATIVOS:-0}${NC}"
    echo -e "  ${MAGENTA}🌐${NC} Com IPv6: ${BOLD}${IPV6:-0}${NC}"
    echo ""

    # 6. Status do Parser
    echo -e "${CYAN}🔹 PARSER:${NC}"
    ULTIMAS_STATS=$(tail -5 /var/log/cgnat/parser.log 2>/dev/null | grep "Stats:" | tail -1)
    if [ ! -z "$ULTIMAS_STATS" ]; then
        CREATED=$(echo "$ULTIMAS_STATS" | grep -oP 'Created=\K[0-9]+' 2>/dev/null || echo "0")
        DELETED=$(echo "$ULTIMAS_STATS" | grep -oP 'Deleted=\K[0-9]+' 2>/dev/null || echo "0")
        CACHE_HITS=$(echo "$ULTIMAS_STATS" | grep -oP 'hits=\K[0-9]+' 2>/dev/null || echo "0")
        CACHE_MISSES=$(echo "$ULTIMAS_STATS" | grep -oP 'misses=\K[0-9]+' 2>/dev/null || echo "0")
        echo -e "  ${GREEN}✅${NC} Processando: Created=${CREATED}, Deleted=${DELETED}"
        echo -e "  ${GREEN}✅${NC} Cache: hits=${CACHE_HITS}, misses=${CACHE_MISSES}"
    else
        echo -e "  ${YELLOW}⚠️${NC} Aguardando primeira leitura..."
    fi
    echo ""

    # 7. Alertas
    echo -e "${CYAN}🔹 ALERTAS:${NC}"
    
    if [[ "$SHM_PERC" =~ ^[0-9]+$ ]] && [ "${SHM_PERC}" -gt 80 ]; then
        echo -e "  ${RED}⚠️${NC} /dev/shm em ${SHM_PERC}% (ATENÇÃO!)"
    fi
    
    if [[ "$DISCO_PERC" =~ ^[0-9]+$ ]] && [ "${DISCO_PERC}" -gt 80 ]; then
        echo -e "  ${RED}⚠️${NC} Disco em ${DISCO_PERC}% (ATENÇÃO!)"
    fi
    
    if [ "${ULTIMO_5MIN:-0}" -eq 0 ] && [ "${TOTAL:-0}" -gt 0 ]; then
        echo -e "  ${YELLOW}⚠️${NC} Nenhum log nos últimos 5 minutos!"
    fi
    
    ERRORS=$(tail -100 /var/log/cgnat/parser.log 2>/dev/null | grep -c "ERROR:")
    if [ $ERRORS -gt 0 ]; then
        echo -e "  ${RED}⚠️${NC} ${ERRORS} erros no parser (últimas 100 linhas)"
    else
        echo -e "  ${GREEN}✅${NC} Nenhum erro no parser"
    fi
    
    echo ""
    echo "============================================================"
    echo "  🔄 Atualiza automaticamente a cada 5 segundos"
    echo "  Pressione Ctrl+C para sair"
    echo "============================================================"
}

# Função: Logs em tempo real
show_logs() {
    echo "============================================================"
    echo "   📋 LOGS EM TEMPO REAL - CGNAT"
    echo "============================================================"
    echo ""
    echo "  🔹 Parser log:     ${GREEN}/var/log/cgnat/parser.log${NC}"
    echo "  🔹 Raw log:        ${GREEN}/var/log/cgnat/raw.log${NC}"
    echo "  🔹 PostgreSQL log: ${GREEN}/var/log/postgresql/postgresql-15-main.log${NC}"
    echo ""
    echo "  Pressione Ctrl+C para sair"
    echo "============================================================"
    echo ""
    
    tail -f \
        /var/log/cgnat/parser.log \
        /var/log/cgnat/raw.log \
        /var/log/postgresql/postgresql-15-main.log 2>/dev/null | \
    while read -r line; do
        if echo "$line" | grep -q "ERROR\|FATAL\|PANIC"; then
            echo -e "${RED}${line}${NC}"
        elif echo "$line" | grep -q "WARNING"; then
            echo -e "${YELLOW}${line}${NC}"
        elif echo "$line" | grep -q "Stats:"; then
            echo -e "${CYAN}${line}${NC}"
        else
            echo "$line"
        fi
    done
}

# Função: Diagnóstico rápido
quick_check() {
    echo "============================================================"
    echo "   ⚡ DIAGNÓSTICO RÁPIDO - $(date '+%d/%m/%Y %H:%M:%S')"
    echo "============================================================"
    echo ""
    
    echo "🔹 SERVIÇOS:"
    for svc in postgresql@15-main rsyslog cgnat-parser apache2; do
        if systemctl is-active --quiet $svc 2>/dev/null; then
            echo "  ✅ $svc"
        else
            echo "  ❌ $svc"
        fi
    done
    echo ""
    
    TOTAL=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM cgnat_logs;" 2>/dev/null | xargs)
    echo "🔹 TOTAL DE LOGS: ${TOTAL:-0}"
    
    ULTIMO_5MIN=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM cgnat_logs WHERE data_hora > NOW() - INTERVAL '5 minutes';" 2>/dev/null | xargs)
    echo "🔹 LOGS ÚLTIMOS 5 MIN: ${ULTIMO_5MIN:-0}"
    echo ""
    
    SHM_PERC=$(df -h /dev/shm | tail -1 | awk '{print $5}' | sed 's/%//')
    echo "🔹 /dev/shm: ${SHM_PERC}%"
    echo ""
    
    echo "🔹 ÚLTIMAS 5 LINHAS DO PARSER:"
    tail -5 /var/log/cgnat/parser.log 2>/dev/null | sed 's/^/  /' || echo "  (sem logs)"
    echo ""
    
    echo "============================================================"
    echo "  Para mais detalhes: monitor_cgnat.sh -d"
    echo "============================================================"
}

# ============================================================
# MAIN
# ============================================================

case "$1" in
    -h|--help)
        show_help
        ;;
    -l|--log)
        show_logs
        ;;
    -d|--dashboard)
        while true; do
            show_dashboard
            sleep 5
        done
        ;;
    -c|--check)
        quick_check
        ;;
    *)
        show_dashboard
        ;;
esac
EOF

chmod +x /usr/local/bin/monitor_cgnat.sh

print_success "Scripts criados com sucesso!"

# Script de Monitoramento de espaço em disco Alertas Telegram
print_header "CRIANDO SCRIPT DE ALERTA TELEGRAM"

cat > /usr/local/bin/check_space.sh << EOF
#!/bin/bash
# ============================================================
# ALERTA DE ESPAÇO EM DISCO - CGNAT (TELEGRAM)
# ============================================================

# Cores
VERDE='\033[0;32m'
VERMELHO='\033[0;31m'
AMARELO='\033[1;33m'
AZUL='\033[0;34m'
NC='\033[0m'

# ============================================================
# CONFIGURAÇÕES DO TELEGRAM
# ============================================================
TELEGRAM_TOKEN="${TEL_TOKEN}"
TELEGRAM_CHAT_ID="${TEL_CHAT_ID}"
TELEGRAM_ENVIO="${TEL_ENVIO}"
MAX_TENTATIVAS="${MAX_TENTATIVAS}"

# ============================================================
# CONFIGURAÇÕES DE ALERTA
# ============================================================
LIMITE_DISCO=75
LIMITE_SHM=80
LOG_FILE="/var/log/cgnat/space_alerts.log"
TEMP_FILE="/tmp/telegram_alert_last.txt"

# ============================================================
# FUNÇÃO: ENVIAR MENSAGEM AO TELEGRAM
# ============================================================
enviar_telegram() {
    local MENSAGEM="\$1"
    local TENTATIVAS=0
    
    if [ "\$TELEGRAM_ENVIO" = "SIM" ]; then
        while [ \$TENTATIVAS -lt \$MAX_TENTATIVAS ]; do
            curl -s -X POST "https://api.telegram.org/bot\${TELEGRAM_TOKEN}/sendMessage" \\
                -d chat_id="\${TELEGRAM_CHAT_ID}" \\
                -d text="\${MENSAGEM}" \\
                -d parse_mode="HTML" > /dev/null 2>&1
            
            if [ \$? -eq 0 ]; then
                echo -e "\${VERDE}✅ Mensagem enviada ao Telegram\${NC}" | tee -a \$LOG_FILE
                return 0
            fi
            
            TENTATIVAS=\$((TENTATIVAS + 1))
            echo -e "\${AMARELO}⚠️ Tentativa \$TENTATIVAS de \$MAX_TENTATIVAS falhou. Tentando novamente...\${NC}" | tee -a \$LOG_FILE
            sleep 2
        done
        
        echo -e "\${VERMELHO}❌ ERRO: Não foi possível enviar mensagem ao Telegram após \$MAX_TENTATIVAS tentativas\${NC}" | tee -a \$LOG_FILE
        return 1
    else
        echo -e "\${AMARELO}ℹ️ Envio para Telegram desativado\${NC}" | tee -a \$LOG_FILE
        return 0
    fi
}

# ============================================================
# FUNÇÃO: GERAR MENSAGEM DE ALERTA
# ============================================================
gerar_mensagem() {
    local TIPO="\$1"
    local VALOR1="\$2"
    local VALOR2="\$3"
    local VALOR3="\$4"
    local VALOR4="\$5"
    local VALOR5="\$6"
    local VALOR6="\$7"
    local HOST=\$(hostname)
    local DATA=\$(date '+%d/%m/%Y %H:%M:%S')
    
    case "\$TIPO" in
        "DISCO")
            echo "🚨 ALERTA DE ESPAÇO EM DISCO - CGNAT

📌 Host: \${HOST}
🕐 Data/Hora: \${DATA}

📊 DISCO:
   Usado: \${VALOR3}
   Uso: \${VALOR1}% (Limite: \${VALOR2}%)

⚠️ AÇÃO RECOMENDADA:
   - Verificar logs antigos
   - Executar limpeza: /usr/local/bin/clean_old_logs.sh
   - Verificar partições: monitor_cgnat.sh -c

🔗 Dashboard: http://\${HOST}/cgnat/"
            ;;
            
        "SHM")
            echo "⚠️ ALERTA DE /dev/shm - CGNAT

📌 Host: \${HOST}
🕐 Data/Hora: \${DATA}

💾 /dev/shm:
   Uso: \${VALOR1}% (Limite: \${VALOR2}%)
   Detalhe: \${VALOR3}

⚠️ AÇÃO RECOMENDADA:
   - Verificar arquivos temporários
   - Executar: /usr/local/bin/clean_shm.sh

🔗 Dashboard: http://\${HOST}/cgnat/"
            ;;
            
        "PARSER")
            echo "🚨 ALERTA CRÍTICO - PARSER PARADO!

📌 Host: \${HOST}
🕐 Data/Hora: \${DATA}

⚠️ O parser CGNAT está PARADO!

📊 Status: \${VALOR3}

🔧 AÇÃO AUTOMÁTICA:
   Sistema tentou reiniciar automaticamente.
   Verifique o status: systemctl status cgnat-parser

🔗 Dashboard: http://\${HOST}/cgnat/"
            ;;
            
        "PARSER_OK")
            echo "✅ PARSER RECUPERADO!

📌 Host: \${HOST}
🕐 Data/Hora: \${DATA}

✅ Parser reiniciado com sucesso!

📊 Status: \${VALOR3}

🔗 Dashboard: http://\${HOST}/cgnat/"
            ;;
            
        "RESUMO")
            echo "📊 RESUMO DIÁRIO - CGNAT

📌 Host: \${HOST}
🕐 Data/Hora: \${DATA}

💾 DISCO:
   \${VALOR3}

🗄️ BANCO DE DADOS:
   Tamanho: \${VALOR1}
   Logs hoje: \${VALOR4}
   Total logs: \${VALOR5}

👥 CLIENTES:
   Total: \${VALOR2}

📊 PARSER:
   \${VALOR6}

🔗 Dashboard: http://\${HOST}/cgnat/"
            ;;
            
        *)
            echo "📊 ALERTA CGNAT

📌 Host: \${HOST}
🕐 Data/Hora: \${DATA}

⚠️ Alerta desconhecido
   Tipo: \${TIPO}
   Detalhe: \${VALOR3}"
            ;;
    esac
}

# ============================================================
# FUNÇÃO: ENVIAR RESUMO DIÁRIO
# ============================================================
enviar_resumo_diario() {
    local FORCAR="\$1"
    
    HOJE=\$(date +%Y%m%d)
    ULTIMO_ENVIO=""
    
    if [ "\$FORCAR" != "force" ] && [ -f "\$TEMP_FILE" ]; then
        ULTIMO_ENVIO=\$(cat "\$TEMP_FILE")
        if [ "\$ULTIMO_ENVIO" = "\$HOJE" ]; then
            echo -e "\${AMARELO}ℹ️ Resumo já enviado hoje. Use --resumo-force para forçar.\${NC}"
            return 0
        fi
    fi
    
    DISCO_INFO=\$(df -h / | tail -1 | awk '{print \$3 " de " \$2 " (" \$5 ")"}')
    DB_SIZE=\$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT pg_size_pretty(pg_database_size('cgnat_logs'));" 2>/dev/null | xargs)
    TOTAL_CLIENTES=\$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM clientes;" 2>/dev/null | xargs)
    LOGS_HOJE=\$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM cgnat_logs WHERE DATE(data_hora) = CURRENT_DATE;" 2>/dev/null | xargs)
    TOTAL_LOGS=\$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM cgnat_logs;" 2>/dev/null | xargs)
    ULTIMA_STATS=\$(tail -5 /var/log/cgnat/parser.log 2>/dev/null | grep "Stats:" | tail -1)
    
    MENSAGEM=\$(gerar_mensagem "RESUMO" "\$DB_SIZE" "\$TOTAL_CLIENTES" "\$DISCO_INFO" "\$LOGS_HOJE" "\$TOTAL_LOGS" "\$ULTIMA_STATS")
    
    enviar_telegram "\$MENSAGEM"
    
    echo "\$HOJE" > "\$TEMP_FILE"
}

# ============================================================
# FUNÇÃO: VERIFICAR E ALERTAR
# ============================================================
verificar_espaco() {
    echo "========================================" >> \$LOG_FILE
    echo "\$(date): Verificando espaço..." >> \$LOG_FILE
    
    USO_DISCO=\$(df -h / | tail -1 | awk '{print \$5}' | sed 's/%//')
    DISCO_INFO=\$(df -h / | tail -1 | awk '{print \$3 " de " \$2}')
    
    if [ \$USO_DISCO -gt \$LIMITE_DISCO ]; then
        echo -e "\${VERMELHO}⚠️ ALERTA: Disco em \${USO_DISCO}%\${NC}" >> \$LOG_FILE
        MENSAGEM=\$(gerar_mensagem "DISCO" "\$USO_DISCO" "\$LIMITE_DISCO" "\$DISCO_INFO")
        enviar_telegram "\$MENSAGEM"
    else
        echo -e "\${VERDE}✅ Disco: \${USO_DISCO}% (OK)\${NC}" >> \$LOG_FILE
    fi
    
    USO_SHM=\$(df -h /dev/shm | tail -1 | awk '{print \$5}' | sed 's/%//')
    SHM_INFO=\$(df -h /dev/shm | tail -1 | awk '{print \$3 " de " \$2}')
    
    if [ \$USO_SHM -gt \$LIMITE_SHM ]; then
        echo -e "\${VERMELHO}⚠️ ALERTA: /dev/shm em \${USO_SHM}%\${NC}" >> \$LOG_FILE
        MENSAGEM=\$(gerar_mensagem "SHM" "\$USO_SHM" "\$LIMITE_SHM" "\$SHM_INFO")
        enviar_telegram "\$MENSAGEM"
    else
        echo -e "\${VERDE}✅ /dev/shm: \${USO_SHM}% (OK)\${NC}" >> \$LOG_FILE
    fi
    
    if ! systemctl is-active --quiet cgnat-parser; then
        echo -e "\${VERMELHO}❌ PARSER PARADO!\${NC}" >> \$LOG_FILE
        MENSAGEM=\$(gerar_mensagem "PARSER" "" "" "Parser está PARADO! Reiniciando...")
        enviar_telegram "\$MENSAGEM"
        
        systemctl restart cgnat-parser
        sleep 5
        
        if systemctl is-active --quiet cgnat-parser; then
            echo -e "\${VERDE}✅ Parser reiniciado com sucesso\${NC}" >> \$LOG_FILE
            MENSAGEM=\$(gerar_mensagem "PARSER_OK" "" "" "Parser reiniciado com sucesso!")
            enviar_telegram "\$MENSAGEM"
        else
            echo -e "\${VERMELHO}❌ FALHA AO REINICIAR PARSER!\${NC}" >> \$LOG_FILE
            MENSAGEM=\$(gerar_mensagem "PARSER" "" "" "FALHA ao reiniciar parser! Verifique manualmente.")
            enviar_telegram "\$MENSAGEM"
        fi
    fi
    
    echo "========================================" >> \$LOG_FILE
}

# ============================================================
# MAIN
# ============================================================

mkdir -p /var/log/cgnat

case "\$1" in
    --resumo|resumo)
        enviar_resumo_diario
        ;;
    --resumo-force|resumo-force)
        enviar_resumo_diario "force"
        ;;
    --test|test)
        echo -e "\${AZUL}🧪 TESTE DE ENVIO AO TELEGRAM\${NC}"
        enviar_telegram "🧪 Teste de conexão - CGNAT%0A%0ASistema funcionando!%0AHost: \$(hostname)%0AData: \$(date)"
        ;;
    *)
        verificar_espaco
        ;;
esac
EOF

chmod +x /usr/local/bin/check_space.sh
print_success "Script de alerta Telegram criado com sucesso!"

# ============================================================
# 15.5. EXECUTAR SINCRONIZAÇÃO INICIAL MKAUTH
# ============================================================
print_header "15.5. EXECUTANDO SINCRONIZAÇÃO INICIAL"

print_info "Populando tabela clientes com dados do MK-AUTH..."
/usr/local/bin/sync_mkauth.sh

if [ $? -eq 0 ]; then
    print_success "Sincronização inicial concluída"
    TOTAL_CLIENTES=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM clientes;" | xargs)
    print_info "Total de clientes importados: ${TOTAL_CLIENTES}"
else
    print_warning "Sincronização inicial falhou. Execute manualmente: /usr/local/bin/sync_mkauth.sh"
fi

print_success "Sincronização inicial finalizada"

# ============================================================
# 15.6.1. EXECUTAR SINCRONIZAÇÃO IPv6 INICIAL CISCO (COM BARRA + TIMEOUT)
# ============================================================
print_header "15.6.1. EXECUTANDO SINCRONIZAÇÃO IPv6 INICIAL"

print_info "Coletando IPv6 dos clientes no Cisco ASR..."

# Marcar tempo de início
INICIO=$(date +%s)

echo ""
echo "⏳ Aguardando sincronização com o Cisco ASR..."
echo "📡 Conectando ao Cisco ASR em ${CISCO_IP}..."
echo ""

# ============================================================
# FUNÇÃO MOSTRAR PROGRESSO (MANTIDA)
# ============================================================
mostrar_progresso() {
    local atual=$1
    local total=$2
    
    if [ -z "$total" ] || [ "$total" -eq 0 ]; then
        printf "\r   ⏳ Processando... (%d clientes sincronizados)" "$atual"
        return
    fi
    
    local tamanho=50
    local progresso=$((atual * tamanho / total))
    local restante=$((tamanho - progresso))
    
    local barra=""
    for ((i=0; i<progresso; i++)); do
        barra="${barra}█"
    done
    for ((i=0; i<restante; i++)); do
        barra="${barra}░"
    done
    
    printf "\r   [%s] %3d%% (%d/%d)" "$barra" $((atual * 100 / total)) $atual $total
}

# ============================================================
# INICIAR SINCRONIZAÇÃO EM BACKGROUND
# ============================================================
/usr/local/bin/sync_ipv6_cisco.sh &
PID=$!

# Buscar clientes ATIVOS
TOTAL_CLIENTES=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM clientes WHERE ativo = true;" 2>/dev/null | xargs)

if [ -z "$TOTAL_CLIENTES" ] || [ "$TOTAL_CLIENTES" -eq 0 ]; then
    TOTAL_CLIENTES=0
    print_warning "Não foi possível obter total de clientes ativos. Acompanhando apenas o número processado."
fi

# ============================================================
# BARRA DE PROGRESSO COM TIMEOUT DE 60 SEGUNDOS
# ============================================================
ATUAL=0
TIMEOUT=60
CONTADOR=0

echo ""
echo "📊 Progresso da sincronização:"
echo ""

while kill -0 $PID 2>/dev/null && [ $CONTADOR -lt $TIMEOUT ]; do
    # Buscar quantos clientes já foram atualizados
    ATUAL=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM clientes WHERE ipv6_atualizado IS NOT NULL AND ipv6_atualizado > NOW() - INTERVAL '5 minutes';" 2>/dev/null | xargs)
    ATUAL=${ATUAL:-0}
    
    if [ "$TOTAL_CLIENTES" -eq 0 ]; then
        printf "\r   ⏳ Processando... (%d clientes sincronizados)" "$ATUAL"
    else
        if [ $ATUAL -gt $TOTAL_CLIENTES ]; then
            ATUAL=$TOTAL_CLIENTES
        fi
        mostrar_progresso $ATUAL $TOTAL_CLIENTES
    fi
    
    sleep 2
    CONTADOR=$((CONTADOR + 2))
done

# ============================================================
# VERIFICAR RESULTADO
# ============================================================
if kill -0 $PID 2>/dev/null; then
    # Timeout: matar o processo
    echo ""
    echo "   ⚠️ Timeout de ${TIMEOUT} segundos. Finalizando..."
    kill -9 $PID 2>/dev/null
    wait $PID 2>/dev/null
    STATUS=124
else
    # Processo terminou normalmente
    wait $PID
    STATUS=$?
fi

# Finalizar a barra
echo ""
if [ "$TOTAL_CLIENTES" -eq 0 ]; then
    echo "   ✅ Processo finalizado! Clientes sincronizados: $ATUAL"
else
    mostrar_progresso $TOTAL_CLIENTES $TOTAL_CLIENTES
fi
echo ""
echo ""

# ============================================================
# CALCULAR TEMPO
# ============================================================
FIM=$(date +%s)
DURACAO=$((FIM - INICIO))
MINUTOS=$((DURACAO / 60))
SEGUNDOS=$((DURACAO % 60))

# ============================================================
# TRATAMENTO DO RESULTADO
# ============================================================
if [ $STATUS -eq 0 ]; then
    echo "✅ Sincronização IPv6 concluída em ${MINUTOS}m${SEGUNDOS}s!"
    print_success "Sincronização IPv6 inicial finalizada"
    
    TOTAL_IPV6=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM clientes WHERE ipv6_prefix IS NOT NULL;" 2>/dev/null | xargs)
    echo "   📊 Total de clientes com IPv6: ${TOTAL_IPV6:-0}"
    
elif [ $STATUS -eq 124 ]; then
    echo "⏰ Timeout: Cisco ASR não respondeu em ${TIMEOUT} segundos."
    print_warning "⚠️ Sincronização IPv6 com timeout - continuando instalação"
    echo "   🔄 O cron tentará novamente a cada 5 minutos"
    echo "   💡 Execute manualmente: /usr/local/bin/sync_ipv6_cisco.sh"
    
else
    echo "❌ Sincronização IPv6 falhou em ${MINUTOS}m${SEGUNDOS}s (código: $STATUS)"
    print_warning "⚠️ Sincronização IPv6 falhou - continuando instalação"
    echo "   🔄 O cron tentará novamente a cada 5 minutos"
    echo "   💡 Execute manualmente: /usr/local/bin/sync_ipv6_cisco.sh"
    echo ""
    echo "   📋 Possíveis causas:"
    echo "      - Cisco ASR não está acessível (IP: ${CISCO_IP})"
    echo "      - Credenciais incorretas"
    echo "      - Firewall bloqueando SSH"
    echo "      - Comando 'show ipv6 dhcp binding' não disponível"
fi

print_info "➡️ Continuando instalação..."
echo ""

# ============================================================
# 15.6.1. MIGRAR DADOS EXISTENTES PARA HISTÓRICO
# ============================================================
print_header "15.6.1. MIGRANDO DADOS IPv6 PARA HISTÓRICO"

print_info "Migrando dados existentes da tabela clientes para historico_ipv6..."

sudo -u postgres psql -d cgnat_logs << 'SQL'
INSERT INTO historico_ipv6 (login, ipv6_prefix, ipv6_address, data_inicio, ativo)
SELECT 
    c.login, 
    c.ipv6_prefix, 
    c.ipv6_address,
    COALESCE(c.ipv6_atualizado, NOW()) as data_inicio,
    true as ativo
FROM clientes c 
WHERE c.ipv6_prefix IS NOT NULL
AND NOT EXISTS (
    SELECT 1 FROM historico_ipv6 h 
    WHERE h.login = c.login 
    AND h.ipv6_prefix = c.ipv6_prefix
);
SQL

TOTAL_HISTORICO=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM historico_ipv6;" 2>/dev/null | xargs)
print_info "Total de registros no histórico IPv6: ${TOTAL_HISTORICO:-0}"
print_success "Migração de histórico IPv6 concluída"

# ============================================================
# 16. AJUSTANDO PERMISSÕES FINAIS
# ============================================================
print_header "16. AJUSTANDO PERMISSÕES FINAIS"

chown -R www-data:www-data /var/www/html/cgnat/ 2>/dev/null || true
chmod -R 755 /var/www/html/cgnat/ 2>/dev/null || true
chmod 644 /var/www/html/cgnat/*.php 2>/dev/null || true

# ============================================================
# CORREÇÃO: PERMISSÕES DO RAW.LOG
# ============================================================
touch /var/log/cgnat/raw.log
if getent group adm >/dev/null 2>&1; then
    chown syslog:adm /var/log/cgnat/raw.log 2>/dev/null || chown root:adm /var/log/cgnat/raw.log
else
    chown syslog:syslog /var/log/cgnat/raw.log 2>/dev/null || chown root:root /var/log/cgnat/raw.log
fi
chmod 640 /var/log/cgnat/raw.log
chmod 755 /var/log/cgnat

# ============================================================
# CORREÇÃO: PERMISSÕES DO PARSER (SELECT + SEQUENCE)
# ============================================================
sudo -u postgres psql -d cgnat_logs << 'SQL' 2>/dev/null || true
-- SELECT nas tabelas
GRANT SELECT ON clientes TO cgnat_parser;
GRANT SELECT ON pppoe_sessoes TO cgnat_parser;
GRANT SELECT ON historico_ipv6 TO cgnat_parser;
GRANT SELECT ON vw_cgnat_logs_count TO cgnat_parser;

-- CRÍTICO: USAGE nas sequences
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO cgnat_parser;

SELECT '✅ Permissões corrigidas' as status;
SQL

# ============================================================
# CORREÇÃO: VERIFICAR RSYSLOG
# ============================================================
if ! systemctl is-active --quiet rsyslog; then
    print_warning "Rsyslog não está rodando. Tentando corrigir..."
    systemctl restart rsyslog
    sleep 2
    if systemctl is-active --quiet rsyslog; then
        print_success "Rsyslog reiniciado com sucesso"
    else
        print_error "Erro ao reiniciar rsyslog. Verifique: journalctl -u rsyslog -n 20"
    fi
fi

# Iniciar serviços
systemctl restart cgnat-parser 2>/dev/null || true
systemctl restart apache2 2>/dev/null || true

print_success "Permissões ajustadas"

# ============================================================
# 17. REDIRECIONAR RAIZ
# ============================================================
print_header "17. CONFIGURANDO REDIRECIONAMENTO"

mv /var/www/html/index.html /var/www/html/index2.html 2>/dev/null || true

cat > /var/www/html/index.php << 'EOF'
<?php
header('Location: /cgnat/login.php');
exit;
?>
EOF

chown www-data:www-data /var/www/html/index.php
chmod 644 /var/www/html/index.php

print_success "Redirecionamento configurado"

# ============================================================
# 18. RESULTADO FINAL
# ============================================================
print_header "✅ INSTALAÇÃO CONCLUÍDA!"

IP=$(hostname -I | awk '{print $1}')

echo "============================================================"
echo "  📋 INFORMAÇÕES DO SISTEMA"
echo "============================================================"
echo ""
echo "🌐 URL de acesso: http://$IP/"
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
echo "   PostgreSQL: systemctl status postgresql@15-main"
echo "   Rsyslog: systemctl status rsyslog"
echo "   Parser: systemctl status cgnat-parser"
echo "   Apache: systemctl status apache2"
echo ""
echo "✅ CORREÇÕES APLICADAS:"
echo "   ✅ raw.log no DISCO (não em /dev/shm)"
echo "   ✅ Permissões SELECT para o parser"
echo "   ✅ /dev/shm com 16GB"
echo "   ✅ Autovacuum otimizado"
echo "   ✅ PostgreSQL fixado (versão 15)"
echo "   ✅ Sincronização MK-AUTH via SSH"
echo "   ✅ Sincronização IPv6 do Cisco ASR"
echo "   ✅ Histórico IPv6 para consultas independentes"
echo ""
echo "📊 PRÓXIMOS PASSOS:"
echo "   1. Acesse a interface web: http://$IP/"
echo "   2. Configure o Cisco ASR1001-X para enviar logs"
echo "   3. Verifique a sincronização MK-AUTH: /usr/local/bin/sync_mkauth.sh"
echo "   4. Verifique a sincronização IPv6: /usr/local/bin/sync_ipv6_cisco.sh"
echo "   5. Dashboard em tempo real (atualiza a cada 5s): monitor_cgnat.sh -d"
echo "   6. Logs em tempo real (tail -f): monitor_cgnat.sh -l"
echo "   7. Diagnóstico rápido: /usr/local/bin/sync_ipv6_cisco.sh"
echo "   8. Ajuda: monitor_cgnat.sh -h"
echo "   9. Dashboard + Logs (tudo): monitor_cgnat.sh -a"
echo "   10. Verificar alertas Telegram: /usr/local/bin/check_space.sh --test"
echo "   11. Resumo diário saúde sistema Telegram: /usr/local/bin/check_space.sh --resumo"
echo ""
echo "============================================================"
print_success "Sistema instalado com sucesso!"
echo "============================================================"
echo ""
echo "📍 João Pessoa - PB"
echo "📅 $(date)"
echo "============================================================"

# ============================================================
# SLEEP DE 5 SEGUNDOS (PARA O USUÁRIO LER A MENSAGEM)
# ============================================================
echo ""
echo "⏳ Aguarde 5 segundos para iniciar o monitoramento..."
sleep 5

# ============================================================
# 19. CONFIGURAR INICIALIZAÇÃO AUTOMÁTICA DO MONITOR
# ============================================================
print_header "19. CONFIGURANDO INICIALIZAÇÃO AUTOMÁTICA DO MONITOR"

print_info "Configurando monitor para iniciar automaticamente..."

# Verificar se o arquivo .bashrc existe
if [ -f /root/.bashrc ]; then
    # Verificar se já foi adicionado antes
    if ! grep -q "INICIAR MONITORAMENTO CGNAT" /root/.bashrc; then
        cat >> /root/.bashrc << 'EOF'

# ============================================================
# INICIAR MONITORAMENTO CGNAT AUTOMATICAMENTE
# (Apenas em terminais interativos, ex: SSH manual)
# ============================================================
if [ -f /usr/local/bin/monitor_cgnat.sh ] && [ -t 0 ]; then
    echo "🚀 Iniciando monitor CGNAT..."
    /usr/local/bin/monitor_cgnat.sh -d
fi
EOF
        print_success "✅ Monitor configurado para iniciar automaticamente!"
        print_info "🔹 Para testar: source /root/.bashrc"
        print_info "🔹 Para sair do monitor: Ctrl+C"
    else
        print_info "ℹ️  Monitor já está configurado no .bashrc"
    fi
else
    print_warning "⚠️  Arquivo /root/.bashrc não encontrado. Criando..."
    touch /root/.bashrc
    cat >> /root/.bashrc << 'EOF'

# ============================================================
# INICIAR MONITORAMENTO CGNAT AUTOMATICAMENTE
# (Apenas em terminais interativos, ex: SSH manual)
# ============================================================
if [ -f /usr/local/bin/monitor_cgnat.sh ] && [ -t 0 ]; then
    echo "🚀 Iniciando monitor CGNAT..."
    /usr/local/bin/monitor_cgnat.sh -d
fi
EOF
    print_success "✅ Monitor configurado para iniciar automaticamente!"
fi

# ============================================================
# 19.1. CONFIGURAR MONITOR NO CONSOLE (BOOT + Ctrl+C)
# ============================================================
print_header "19.1. CONFIGURANDO MONITOR NO CONSOLE FÍSICO"

print_info "Configurando monitor para iniciar automaticamente no boot..."

# Criar serviço systemd
cat > /etc/systemd/system/cgnat-console.service << 'EOF'
[Unit]
Description=CGNAT Monitor on Console
After=network.target postgresql.service
Wants=postgresql.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/monitor_cgnat.sh -d
Restart=always
RestartSec=5
StandardInput=tty
StandardOutput=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes

[Install]
WantedBy=multi-user.target
EOF

# Habilitar e iniciar
systemctl daemon-reload
systemctl enable cgnat-console.service
systemctl start cgnat-console.service

print_success "✅ Monitor configurado no console físico!"
print_info "🔹 Após o boot, o dashboard será exibido automaticamente"
print_info "🔹 Para sair do dashboard: Ctrl+C"
print_info "🔹 Para voltar ao dashboard: monitor_cgnat.sh -d"
print_info "🔹 SSH continua normal"

# ============================================================
# INICIAR MONITORAMENTO AUTOMATICAMENTE APÓS A INSTALAÇÃO
# ============================================================
print_info "Iniciando monitoramento em 5 segundos..."
sleep 5

# Executar o monitor em background (ou foreground)
/usr/local/bin/monitor_cgnat.sh -d

# ============================================================
# FIM DO SCRIPT
# ============================================================
