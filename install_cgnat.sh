#!/bin/bash
# ============================================================
# SCRIPT DE INSTALAÇÃO - SISTEMA CGNAT LGPD
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

DB_PASS_CGNAT="WBT@00000000"
DB_PASS_PARSER="WBT@0000000"
MK_AUTH_IP="172.31.254.2"
MK_AUTH_USER="root"
MK_AUTH_PASS="00000000@MLSS"
MK_AUTH_DB_PASS="vertrigo"
CISCO_IP="192.168.243.250"
CISCO_USER="mkauth"
CISCO_PASS="WBT@0000000"
TIMEZONE="America/Recife"

# ============================================================
# INÍCIO
# ============================================================

clear
print_header "🚀 INSTALADOR CGNAT LGPD - SISTEMA COMPLETO"
echo "📌 Versão para João Pessoa/PB"
echo ""
echo "Serão instalados:"
echo "  ✅ PostgreSQL 15 com banco de dados"
echo "  ✅ Python 3 com ambiente virtual"
echo "  ✅ Apache2 + PHP"
echo "  ✅ Rsyslog para recebimento de logs"
echo "  ✅ Parser de logs CGNAT"
echo "  ✅ Interface web completa (TODAS AS PÁGINAS)"
echo "  ✅ Scripts de backup e monitoramento"
echo "  ✅ Integração com MK-AUTH (usando sis_cliente e sis_adicional)"
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
# 2.5. CORRIGIR HOSTNAME NO /ETC/HOSTS
# ============================================================
print_header "2.5. CORRIGINDO HOSTNAME NO /ETC/HOSTS"

# Adicionar hostname ao /etc/hosts para evitar erros no sudo
if ! grep -q "$(hostname)" /etc/hosts; then
    echo "127.0.1.1 $(hostname)" >> /etc/hosts
    print_success "Hostname adicionado ao /etc/hosts"
else
    print_success "Hostname já está no /etc/hosts"
fi

# ============================================================
# 3. ATUALIZAR SISTEMA
# ============================================================
print_header "3. ATUALIZANDO SISTEMA"
apt update
apt upgrade -y
print_success "Sistema atualizado"

# ============================================================
# 4. INSTALAR PACOTES (COM DETECÇÃO DE VERSÃO DO DEBIAN)
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

# Instalar pacotes base (incluindo gnupg e ferramentas de diagnóstico)
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
    sysstat

# PHP e extensões (compatível com PHP 8.x)
print_info "Instalando PHP e extensões..."
apt install -y \
    php \
    php-pgsql \
    php-curl \
    php-mbstring

print_success "Pacotes base instalados"

# Instalar mysql_fdw de acordo com a versão do Debian
print_info "Instalando postgresql-15-mysql-fdw..."

if dpkg -l 2>/dev/null | grep -q "postgresql-15-mysql-fdw"; then
    print_info "postgresql-15-mysql-fdw já está instalado"
else
    case "${DEBIAN_VERSION}" in
        12|bookworm)
            print_info "Debian 12 - Instalando pacote nativo"
            apt install -y postgresql-15-mysql-fdw
            ;;
        13|trixie)
            print_info "Debian 13 - Adicionando repositório PGDG..."
            mkdir -p /usr/share/keyrings
            if command -v gpg &> /dev/null; then
                curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg
            else
                wget -q -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
            fi
            echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt ${DEBIAN_CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list
            apt update
            apt install -y postgresql-15-mysql-fdw
            ;;
        *)
            print_warning "Versão não reconhecida. Usando PGDG..."
            mkdir -p /usr/share/keyrings
            if command -v gpg &> /dev/null; then
                curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /usr/share/keyrings/pgdg.gpg
            else
                wget -q -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add -
            fi
            echo "deb [signed-by=/usr/share/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt ${DEBIAN_CODENAME}-pgdg main" > /etc/apt/sources.list.d/pgdg.list
            apt update
            apt install -y postgresql-15-mysql-fdw
            ;;
    esac
fi

print_success "Pacotes instalados com sucesso!"

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
# 6. CONFIGURAR POSTGRESQL (COMPATÍVEL DEBIAN 12 E 13)
# ============================================================
print_header "6. CONFIGURANDO POSTGRESQL"

# Parar qualquer instância existente
systemctl stop postgresql 2>/dev/null || true
systemctl stop postgresql@15-main 2>/dev/null || true
systemctl stop postgresql@17-main 2>/dev/null || true

# Verificar versões disponíveis
PG_AVAILABLE=$(ls /usr/lib/postgresql/ 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -1)
print_info "Versões do PostgreSQL disponíveis: $(ls /usr/lib/postgresql/ 2>/dev/null | grep -E '^[0-9]+$' | tr '\n' ' ')"

# Determinar qual versão usar (priorizar 15)
if [ -d "/usr/lib/postgresql/15" ]; then
    PG_VERSION="15"
elif [ -d "/usr/lib/postgresql/14" ]; then
    PG_VERSION="14"
elif [ -d "/usr/lib/postgresql/13" ]; then
    PG_VERSION="13"
else
    PG_VERSION=$(ls /usr/lib/postgresql/ 2>/dev/null | grep -E '^[0-9]+$' | sort -n | head -1)
fi

print_info "Versão do PostgreSQL selecionada: ${PG_VERSION}"

# Remover clusters existentes
pg_dropcluster ${PG_VERSION} main --stop 2>/dev/null || true
rm -rf /var/lib/postgresql/${PG_VERSION}/main 2>/dev/null || true
rm -f /var/run/postgresql/.s.PGSQL.5432 2>/dev/null || true
rm -f /var/run/postgresql/.s.PGSQL.5432.lock 2>/dev/null || true

# Criar novo cluster com porta 5432
pg_createcluster ${PG_VERSION} main --start -u postgres -p 5432

# Otimizar configuração do PostgreSQL
CONF_FILE="/etc/postgresql/${PG_VERSION}/main/postgresql.conf"
if [ -f "$CONF_FILE" ]; then
    # Garantir porta 5432
    sed -i "s/^port =.*/port = 5432/" "$CONF_FILE" 2>/dev/null || echo "port = 5432" >> "$CONF_FILE"
    
    # Otimizações de performance
    echo "" >> "$CONF_FILE"
    echo "# Otimizações CGNAT" >> "$CONF_FILE"
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
fi

# Iniciar PostgreSQL da versão correta
systemctl start postgresql@${PG_VERSION}-main
systemctl enable postgresql@${PG_VERSION}-main
sleep 5

# Parar outras versões se estiverem rodando
for ver in $(ls /usr/lib/postgresql/ 2>/dev/null | grep -E '^[0-9]+$'); do
    if [ "$ver" != "$PG_VERSION" ] && systemctl is-active --quiet postgresql@${ver}-main 2>/dev/null; then
        print_info "Parando PostgreSQL ${ver} para evitar conflito..."
        systemctl stop postgresql@${ver}-main
        systemctl disable postgresql@${ver}-main 2>/dev/null || true
    fi
done

# Verificar se está rodando
if ! systemctl is-active --quiet postgresql@${PG_VERSION}-main; then
    print_warning "Tentando iniciar com pg_ctlcluster..."
    pg_ctlcluster ${PG_VERSION} main start
    sleep 3
fi

if ! systemctl is-active --quiet postgresql@${PG_VERSION}-main; then
    print_error "Não foi possível iniciar o PostgreSQL"
    pg_lsclusters
    journalctl -u postgresql -n 10 --no-pager
    exit 1
fi

print_success "PostgreSQL ${PG_VERSION} rodando na porta 5432"

# Verificar conexão
if sudo -u postgres psql -c "SELECT 1" 2>/dev/null; then
    print_success "PostgreSQL respondendo corretamente"
else
    print_error "PostgreSQL não responde"
    exit 1
fi

# ============================================================
# 7. CRIAR USUÁRIOS E BANCO
# ============================================================
print_header "7. CRIANDO USUÁRIOS E BANCO"

sudo -u postgres psql -c "CREATE USER cgnat_parser WITH PASSWORD 'WBT@0000000';" 2>/dev/null || true
sudo -u postgres psql -c "CREATE USER cgnat_admin WITH PASSWORD 'WBT@00000000';" 2>/dev/null || true
sudo -u postgres psql -c "CREATE DATABASE cgnat_logs OWNER cgnat_parser;" 2>/dev/null || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE cgnat_logs TO cgnat_parser;" 2>/dev/null || true
sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE cgnat_logs TO cgnat_admin;" 2>/dev/null || true
sudo -u postgres psql -d cgnat_logs -c "CREATE EXTENSION IF NOT EXISTS dblink;" 2>/dev/null || true

print_success "Usuários e banco criados"

# ============================================================
# 8. CRIAR TABELAS (COM AS NOVAS COLUNAS PARA LGPD E IPv6)
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
    criado_em TIMESTAMP DEFAULT NOW()
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

-- VIEW para contagem rápida de logs
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

-- Permissões
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO cgnat_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO cgnat_admin;
GRANT INSERT ON cgnat_logs TO cgnat_parser;
GRANT INSERT ON clientes TO cgnat_parser;
GRANT SELECT ON vw_cgnat_logs_count TO cgnat_admin;
GRANT SELECT ON vw_cgnat_logs_count TO cgnat_parser;

-- Criação de partições
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
    
    EXECUTE format('
        CREATE INDEX IF NOT EXISTS %I ON %I(ipv6_cliente)
    ', 'idx_' || nome_particao || '_ipv6', nome_particao);
END $$;
EOF

print_success "Tabelas criadas com as novas colunas LGPD e IPv6"

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
# 10. CRIAR O PARSER PYTHON (VERSÃO OTIMIZADA)
# ============================================================
print_header "10. CRIANDO PARSER PYTHON"

cat > /opt/cgnat/cgnat_parser.py << 'EOF'
#!/usr/bin/env python3
# /opt/cgnat/cgnat_parser.py - VERSÃO OTIMIZADA COM CACHE

import re
import sys
import psycopg2
from datetime import datetime
import logging
from typing import Dict, Optional, Tuple

# Configurar logging - Nível WARNING para reduzir I/O
logging.basicConfig(
    filename='/var/log/cgnat/parser.log',
    level=logging.WARNING,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

class CGNATParserASR:
    def __init__(self):
        self.conn = psycopg2.connect(
            host="localhost",
            database="cgnat_logs",
            user="cgnat_parser",
            password="WBT@0000000"
        )
        self.conn.autocommit = False
        
        # Pré-compilar expressões regulares para melhor performance
        self.timestamp_pattern = re.compile(r'(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\.\d{3})')
        self.nat_pattern = re.compile(r'%NAT-6-LOG_TRANSLATION:\s+(.+)')
        self.translation_pattern = re.compile(
            r'(Created|Deleted)\s+Translation\s+(\w+)\s+([\d.]+):(\d+)\s+([\d.]+):(\d+)\s+([\d.]+):(\d+)\s+([\d.]+):(\d+)\s+(\d+)'
        )
        
        # Estatísticas
        self.stats = {
            'created': 0,
            'deleted': 0,
            'errors': 0,
            'found_in_clientes': 0,
            'found_in_pppoe': 0,
            'not_found': 0
        }
        
        # Cache de logins (evita consultas repetidas ao banco)
        self.login_cache = {}
        self.cache_hits = 0
        self.cache_misses = 0
        
    def parse_log_line(self, line: str) -> Optional[Dict]:
        timestamp_match = self.timestamp_pattern.search(line)
        if timestamp_match:
            data_hora = self.parse_cisco_timestamp(timestamp_match.group(1))
        else:
            data_hora = datetime.now()
        
        nat_match = self.nat_pattern.search(line)
        if not nat_match:
            return None
            
        nat_message = nat_match.group(1)
        match = self.translation_pattern.search(nat_message)
        
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
        # Verificar cache primeiro
        if ip_privado in self.login_cache:
            self.cache_hits += 1
            return self.login_cache[ip_privado], None
        
        self.cache_misses += 1
        cursor = self.conn.cursor()
        try:
            # PRIMEIRO: Buscar na tabela clientes (MK-AUTH)
            cursor.execute("""
                SELECT login
                FROM clientes
                WHERE ip_privado = %s::inet
                LIMIT 1
            """, (ip_privado,))
            
            result = cursor.fetchone()
            if result:
                self.stats['found_in_clientes'] += 1
                self.login_cache[ip_privado] = result[0]
                return result[0], None
            
            # SEGUNDO: Buscar na tabela pppoe_sessoes (fallback)
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
                self.stats['found_in_pppoe'] += 1
                self.login_cache[ip_privado] = result[0]
                return result[0], result[1]
            
            self.stats['not_found'] += 1
            self.login_cache[ip_privado] = None
            return None, None
            
        except Exception as e:
            return None, None
        finally:
            cursor.close()
    
    def save_log(self, parsed: Dict):
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
            self.conn.rollback()
            self.stats['errors'] += 1
        finally:
            cursor.close()
    
    def process_line(self, line: str):
        try:
            parsed = self.parse_log_line(line)
            if parsed:
                self.save_log(parsed)
            else:
                self.stats['errors'] += 1
        except Exception:
            self.stats['errors'] += 1
    
    def run(self):
        logging.warning("Parser CGNAT iniciado - VERSÃO OTIMIZADA COM CACHE")
        
        for line in sys.stdin:
            line = line.strip()
            if not line or '%NAT-6-LOG_TRANSLATION' not in line:
                continue
            self.process_line(line)
            
            if (self.stats['created'] + self.stats['deleted']) % 5000 == 0:
                logging.warning(f"Stats: Created={self.stats['created']}, Deleted={self.stats['deleted']}, "
                           f"Cache: hits={self.cache_hits}, misses={self.cache_misses}, "
                           f"Found in clientes={self.stats['found_in_clientes']}, "
                           f"Not found={self.stats['not_found']}")

if __name__ == "__main__":
    parser = CGNATParserASR()
    parser.run()
EOF

chmod +x /opt/cgnat/cgnat_parser.py
print_success "Parser Python criado com otimizações (cache e regex pré-compilados)"

# ============================================================
# 11. CRIAR SERVICE DO PARSER (COM OTIMIZAÇÕES)
# ============================================================
print_header "11. CRIANDO SERVICE DO PARSER"

cat > /etc/systemd/system/cgnat-parser.service << 'EOF'
[Unit]
Description=CGNAT Log Parser Service
After=network.target postgresql.service rsyslog.service

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
# Otimizações de performance
CPUQuota=80%
Nice=-10
IOSchedulingClass=realtime
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cgnat-parser
systemctl start cgnat-parser

print_success "Service do parser criado com otimizações"

# ============================================================
# 12. CRIAR TODOS OS ARQUIVOS PHP
# ============================================================
print_header "12. CRIANDO ARQUIVOS PHP"

# 12.1 CONFIG.PHP
cat > /var/www/html/cgnat/config.php << 'CONFIG_PHP'
<?php
define('DB_HOST', 'localhost');
define('DB_NAME', 'cgnat_logs');
define('DB_USER', 'cgnat_admin');
define('DB_PASS', 'WBT@00000000');
define('MK_AUTH_HOST', '172.31.255.2');
define('MK_AUTH_DB', 'mkradius');
define('MK_AUTH_USER', 'root');
define('MK_AUTH_PASS', 'vertrigo');
date_default_timezone_set('America/Recife');
if (session_status() == PHP_SESSION_NONE) {
    session_start();
}
?>
CONFIG_PHP

# ============================================================
# 12.1.1 HEADERS.PHP (ANTI-CACHE) - NOVO
# ============================================================
cat > /var/www/html/cgnat/headers.php << 'HEADERS_PHP'
<?php
// Headers anti-cache para navegadores
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');
header('Cache-Control: post-check=0, pre-check=0', false);
header('Pragma: no-cache');
header('Expires: Thu, 01 Jan 1970 00:00:00 GMT');
?>
HEADERS_PHP

# 12.2 FUNCTIONS.PHP
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

# 12.3 AUTH.PHP
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

# 12.4 LOGIN.PHP
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

# 12.5 LOGOUT.PHP
cat > /var/www/html/cgnat/logout.php << 'LOGOUT_PHP'
<?php
session_start();
session_destroy();
header('Location: login.php');
exit;
?>
LOGOUT_PHP

# 12.6 MENU.PHP
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
    <a href="index.php" class="logo">📡 CGNAT LGPD</a>
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

# ============================================================
# 12.7 INDEX.PHP (DESIGN MODERNO E FONTE IGUAL AOS CARDS)
# ============================================================
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

        /* Header moderno */
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

        /* Card de disco moderno (mesmo estilo dos cards) */
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

        /* Cards de métricas */
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

        /* Botão moderno */
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

        @media (max-width: 768px) {
            .cards { grid-template-columns: 1fr 1fr; }
            .header-index { flex-direction: column; align-items: stretch; }
            .disco-card-header { align-self: stretch; }
        }
        @media (max-width: 480px) {
            .cards { grid-template-columns: 1fr; }
            .disco-card-header .numero { font-size: 24px; }
        }
    </style>
</head>
<body>
    <div class="container">
        <!-- Header: Boas-vindas + Card de Disco lado a lado -->
        <div class="header-index">
            <div class="welcome">
                <h1>👋 Bem-vindo, <span class="user"><?php echo htmlspecialchars($_SESSION['nome_completo']); ?></span></h1>
                <p>Sistema de Consulta CGNAT para atendimento à LGPD.</p>
                <div class="perfil">Perfil: <strong><?php echo htmlspecialchars($_SESSION['perfil']); ?></strong></div>
            </div>

            <!-- Card de Disco (mesmo estilo e tamanho dos cards) -->
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

        <!-- Cards de métricas (4 colunas) -->
        <div class="cards">
            <div class="card card-verde">
                <div class="numero"><?php echo $consultas_hoje; ?></div>
                <div class="label">Consultas Hoje</div>
            </div>
            <div class="card card-vermelho">
                <div class="numero" id="total_logs"><?php echo number_format($total_logs); ?></div>
                <div class="label">Total de Logs CGNAT</div>
            </div>
            <div class="card card-amarelo">
                <div class="numero"><?php echo number_format($total_clientes); ?></div>
                <div class="label">Clientes Cadastrados</div>
            </div>
            <div class="card">
                <div class="numero"><?php echo date('d/m/Y'); ?></div>
                <div class="label">Data Atual</div>
            </div>
        </div>

        <!-- Botão Consultar -->
        <div class="actions">
            <a href="consultar.php" class="btn-consulta">🔍 Ir para Consultas</a>
        </div>
    </div>

    <!-- Atualização automática a cada 30 segundos -->
    <script>
    setTimeout(function() {
        location.reload();
    }, 5000);
    </script>
</body>
</html>
INDEX_PHP

# ============================================================
# 12.8 DASHBOARD.PHP (COM ATUALIZAÇÃO AUTOMÁTICA)
# ============================================================
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
                            <th>IP Privado</th>
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
    
    <!-- Atualização automática a cada 15 segundos -->
    <script>
    setTimeout(function() {
        location.reload();
    }, 15000);
    </script>
</body>
</html>
DASHBOARD_PHP

# 12.9 CONSULTAR.PHP
cat > /var/www/html/cgnat/consultar.php << 'CONSULTAR_PHP'
<?php
require_once 'headers.php';
require_once 'auth.php';
verificarPermissao();
require_once 'functions.php';

// Forçar timezone correto para este arquivo
date_default_timezone_set('America/Recife');

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

// Data atual no timezone correto
$data_atual = date('Y-m-d');

// Verificar se veio via GET (reabrir consulta)
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
    
    // VALIDAÇÃO: Pelo menos IP+Porta OU IPv6 deve ser preenchido
    if (empty($ip_publico) && empty($ipv6_busca)) {
        $mensagem = '⚠️ Preencha pelo menos o IP Público + Porta, ou o IPv6.';
    } elseif (!empty($ip_publico) && empty($porta)) {
        $mensagem = '⚠️ Se informar o IP Público, a Porta Pública é obrigatória.';
    } else {
        try {
            $db = getDBConnection();
            
            // CONSTRUIR A CONSULTA DINAMICAMENTE
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
                    COALESCE(cl.nome, c.login) as cliente_nome,
                    c.login as cliente_login,
                    cl.ipv6_prefix,
                    cl.nome as cliente_nome_real
                FROM cgnat_logs c
                LEFT JOIN clientes cl ON c.login = cl.login
                WHERE 1=1
            ";
            
            $params = [];
            $cliente_nome_encontrado = '';
            $ip_privado_encontrado = null;
            $ipv6_prefix_encontrado = null;
            
            // Filtro por IP Público e Porta
            if (!empty($ip_publico) && !empty($porta)) {
                $sql .= " AND c.ip_publico = ?::inet AND c.porta_publica = ?";
                $params[] = $ip_publico;
                $params[] = (int)$porta;
            }
            
            // Filtro por IPv6
            if (!empty($ipv6_busca)) {
                $ipv6_normalizado = $ipv6_busca;
                
                if (strpos($ipv6_busca, ':') !== false && strpos($ipv6_busca, '/') === false) {
                    $parts = explode(':', $ipv6_busca);
                    if (count($parts) >= 4) {
                        $prefixo_parts = array_slice($parts, 0, 3);
                        $quarta_parte = isset($parts[3]) ? $parts[3] : '0000';
                        $ipv6_normalizado = implode(':', $prefixo_parts) . ':' . $quarta_parte . '::/56';
                    }
                }
                
                $stmt_login = $db->prepare("
                    SELECT login, ip_privado, ipv6_prefix, nome
                    FROM clientes 
                    WHERE UPPER(ipv6_prefix) = UPPER(?)
                ");
                $stmt_login->execute([$ipv6_normalizado]);
                $cliente_ipv6 = $stmt_login->fetch(PDO::FETCH_ASSOC);
                
                if (!$cliente_ipv6) {
                    if (strpos($ipv6_busca, ':') !== false) {
                        $parts = explode(':', $ipv6_busca);
                        $prefixo_busca = '';
                        if (count($parts) >= 4) {
                            $prefixo_busca = $parts[0] . ':' . $parts[1] . ':' . $parts[2] . ':' . $parts[3] . '::/56';
                        }
                        if (!empty($prefixo_busca)) {
                            $stmt_login = $db->prepare("
                                SELECT login, ip_privado, ipv6_prefix, nome
                                FROM clientes 
                                WHERE UPPER(ipv6_prefix) = UPPER(?)
                            ");
                            $stmt_login->execute([$prefixo_busca]);
                            $cliente_ipv6 = $stmt_login->fetch(PDO::FETCH_ASSOC);
                        }
                    }
                }
                
                if ($cliente_ipv6) {
                    $cliente_nome_encontrado = $cliente_ipv6['nome'] ?? $cliente_ipv6['login'];
                    $ip_privado_encontrado = $cliente_ipv6['ip_privado'];
                    $ipv6_prefix_encontrado = $cliente_ipv6['ipv6_prefix'];
                    
                    $sql .= " AND c.ip_privado = ?::inet";
                    $params[] = $cliente_ipv6['ip_privado'];
                } else {
                    $sql .= " AND UPPER(c.ipv6_cliente::text) LIKE UPPER(?)";
                    $params[] = '%' . $ipv6_busca . '%';
                }
            }
            
            // Filtro por data/hora
            $sql .= " AND c.data_hora BETWEEN ? AND ?";
            $params[] = $data_inicio;
            $params[] = $data_fim;
            
            $sql .= " ORDER BY c.data_hora DESC LIMIT 1000";
            
            $stmt = $db->prepare($sql);
            $stmt->execute($params);
            $resultados = $stmt->fetchAll(PDO::FETCH_ASSOC);
            $total = count($resultados);
            
            // Pegar informações do primeiro resultado
            if ($total > 0) {
                $primeiro = $resultados[0];
                if (!empty($cliente_nome_encontrado)) {
                    $cliente_nome = $cliente_nome_encontrado;
                } else {
                    $cliente_nome = $primeiro['cliente_nome'] ?? 'Nao identificado';
                }
                $ip_privado = $ip_privado_encontrado ?? $primeiro['ip_privado'] ?? null;
                $ipv6_prefix = $ipv6_prefix_encontrado ?? $primeiro['ipv6_prefix'] ?? null;
                $log_data_hora = $primeiro['data_hora'] ?? null;
                $log_acao = $primeiro['acao'] ?? null;
                $log_destino = ($primeiro['ip_destino'] ?? '') . ':' . ($primeiro['porta_destino'] ?? '');
                $log_protocolo = $primeiro['protocolo'] ?? null;
            }
            
            // SALVAR NA TABELA lgpd_audit
            $ip_publico_sql = !empty($ip_publico) ? $ip_publico : null;
            $porta_sql = !empty($porta) ? (int)$porta : null;
            $ip_privado_sql = !empty($ip_privado) ? $ip_privado : null;
            $ipv6_prefix_sql = !empty($ipv6_prefix) ? $ipv6_prefix : null;
            $log_data_hora_sql = !empty($log_data_hora) ? $log_data_hora : null;
            $ip_origem = !empty($_SERVER['REMOTE_ADDR']) ? $_SERVER['REMOTE_ADDR'] : null;
            
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
                $ip_publico_sql,
                $porta_sql,
                $motivo,
                $protocolo,
                $ip_privado_sql,
                $cliente_nome ?: 'Nao identificado',
                $ipv6_prefix_sql,
                $log_data_hora_sql,
                $log_acao,
                $log_destino,
                $log_protocolo,
                $total,
                $ip_origem,
                $_SERVER['HTTP_USER_AGENT'] ?? null
            ]);
            
            $mensagem = $total > 0 ? "✅ Encontrados {$total} registros." : '⚠️ Nenhum registro encontrado para os parâmetros informados.';
            
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
        .container { max-width: 1200px; margin: 0 auto; background: white; border-radius: 10px; padding: 30px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
        h1 { color: #333; border-bottom: 3px solid #667eea; padding-bottom: 15px; margin-bottom: 25px; }
        .row { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
        .form-group { margin-bottom: 20px; }
        label { display: block; font-weight: 600; margin-bottom: 5px; color: #555; }
        input { width: 100%; padding: 12px; border: 2px solid #e0e0e0; border-radius: 8px; font-size: 14px; }
        input:focus { border-color: #667eea; outline: none; }
        .btn { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; border: none; padding: 15px 40px; border-radius: 8px; font-size: 16px; font-weight: 600; cursor: pointer; }
        .btn:hover { opacity: 0.9; }
        .btn-danger { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); }
        .results { margin-top: 30px; border-top: 2px solid #eee; padding-top: 20px; overflow-x: auto; }
        table { width: 100%; border-collapse: collapse; font-size: 14px; }
        th { background: #f8f9fa; padding: 12px; text-align: left; border-bottom: 2px solid #dee2e6; white-space: nowrap; }
        td { padding: 10px; border-bottom: 1px solid #eee; }
        tr:hover { background: #f8f9fa; }
        .badge { display: inline-block; padding: 3px 10px; border-radius: 20px; font-size: 12px; font-weight: 600; }
        .badge-success { background: #d4edda; color: #155724; }
        .badge-danger { background: #f8d7da; color: #721c24; }
        .badge-info { background: #cce5ff; color: #004085; }
        .badge-ipv6 { background: #d1ecf1; color: #0c5460; padding: 3px 10px; border-radius: 20px; font-size: 12px; font-weight: 600; display: inline-block; font-family: monospace; }
        .alert { padding: 15px; border-radius: 8px; margin-bottom: 20px; }
        .alert-success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .alert-danger { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .alert-warning { background: #fff3cd; color: #856404; border: 1px solid #ffeeba; }
        .client-info { background: #e7f3ff; padding: 15px; border-radius: 8px; margin: 15px 0; border-left: 4px solid #667eea; }
        .client-info h3 { color: #004085; margin: 0; }
        .client-info p { margin-top: 5px; color: #555; font-size: 14px; }
        .text-muted { color: #999; }
        .info-required { font-size: 12px; color: #888; margin-top: 5px; }
        @media (max-width: 768px) { .row { grid-template-columns: 1fr; } }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 Consulta CGNAT - LGPD</h1>
        
        <?php if ($mensagem): ?>
        <div class="alert alert-<?php echo strpos($mensagem, 'Nenhum') !== false ? 'warning' : (strpos($mensagem, 'Erro') !== false ? 'danger' : 'success'); ?>">
            <?php echo $mensagem; ?>
        </div>
        <?php endif; ?>
        
        <?php if ($cliente_nome && $cliente_nome != 'Nao identificado'): ?>
        <div class="client-info">
            <h3>👤 Cliente: <?php echo htmlspecialchars($cliente_nome); ?></h3>
            <?php if ($ip_privado): ?>
            <p>📍 IP Privado: <strong><?php echo htmlspecialchars($ip_privado); ?></strong></p>
            <?php endif; ?>
            <?php if ($ipv6_prefix): ?>
            <p>🌐 IPv6: <strong><?php echo htmlspecialchars($ipv6_prefix); ?></strong></p>
            <?php endif; ?>
        </div>
        <?php endif; ?>
        
        <form method="POST" id="formConsulta">
            <div class="row">
                <div class="form-group">
                    <label>IP Público</label>
                    <input type="text" name="ip_publico" id="ip_publico" placeholder="Ex: 190.196.242.18" value="<?php echo htmlspecialchars($_POST['ip_publico'] ?? ''); ?>">
                </div>
                <div class="form-group">
                    <label>Porta Pública</label>
                    <input type="number" name="porta" id="porta" placeholder="Ex: 51478" value="<?php echo htmlspecialchars($_POST['porta'] ?? ''); ?>">
                    <div class="info-required">Obrigatório se informar IP Público</div>
                </div>
            </div>
            <div class="row">
                <div class="form-group">
                    <label>IPv6 do Cliente <span style="color:#888;font-weight:normal;">(ou use IP+Porta)</span></label>
                    <input type="text" name="ipv6_busca" id="ipv6_busca" placeholder="Ex: 2804:3B80:5000:CD00:20D8:2EDF:060F:E1A3" value="<?php echo htmlspecialchars($_POST['ipv6_busca'] ?? ''); ?>">
                    <div class="info-required">Informe o IP+Porta OU o IPv6 para consultar</div>
                </div>
                <div class="form-group">
                    <label>&nbsp;</label>
                </div>
            </div>
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
            <div class="row">
                <div class="form-group">
                    <label>Motivo</label>
                    <input type="text" name="motivo" id="motivo" value="Consulta LGPD">
                </div>
                <div class="form-group">
                    <label>Protocolo Judicial</label>
                    <input type="text" name="protocolo" id="protocolo" placeholder="Número do processo">
                </div>
            </div>
            <button type="submit" class="btn">🔍 Consultar</button>
            <button type="button" class="btn btn-danger" onclick="limparFormulario()" style="margin-left:10px;">↺ Limpar</button>
        </form>
        
        <?php if ($resultados && $total > 0): ?>
        <div class="results">
            <h3>📋 Resultados (<?php echo $total; ?> registros)</h3>
            <table>
                <thead>
                    <tr>
                        <th>Data/Hora</th>
                        <th>Evento</th>
                        <th>IP Cliente</th>
                        <th>Porta</th>
                        <th>IP Público</th>
                        <th>Porta Pública</th>
                        <th>Destino</th>
                        <th>Protocolo</th>
                        <th>Cliente</th>
                        <th>IPv6</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach ($resultados as $row): ?>
                    <tr>
                        <td><?php echo htmlspecialchars($row['data_hora']); ?></td>
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
                            <?php if (!empty($row['cliente_nome'])): ?>
                                <span class="badge badge-info"><?php echo htmlspecialchars($row['cliente_nome']); ?></span>
                            <?php elseif (!empty($row['cliente_login'])): ?>
                                <span class="badge badge-info"><?php echo htmlspecialchars($row['cliente_login']); ?></span>
                            <?php else: ?>
                                <span class="text-muted">Não identificado</span>
                            <?php endif; ?>
                        </td>
                        <td>
                            <?php if (!empty($row['ipv6_prefix'])): ?>
                                <span class="badge-ipv6"><?php echo htmlspecialchars($row['ipv6_prefix']); ?></span>
                            <?php else: ?>
                                <span class="text-muted">-</span>
                            <?php endif; ?>
                        </td>
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>
        <?php endif; ?>
    </div>
    
    <script>
    function limparFormulario() {
        // Usar a data atual no timezone correto (via PHP)
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

# 12.10 RELATORIOS.PHP
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
        
        <h3 style="margin-top:30px;">📋 Últimas Consultas <small style="font-weight:normal;color:#888;">(clique em "Reabrir" para ver os resultados)</small></h3>
        <table>
            <thead>
                <tr>
                    <th>Data</th>
                    <th>Usuário</th>
                    <th>IP</th>
                    <th>Porta</th>
                    <th>Cliente</th>
                    <th>IP Privado</th>
                    <th>IPv6</th>
                    <th>Motivo</th>
                    <th>Ação</th>
                </tr>
            </thead>
            <tbody>
                <?php if ($ultimas): foreach ($ultimas as $row): 
                    // Construir o link de reabrir corretamente
                    $link_params = [];
                    if (!empty($row['ip_consultado']) && !empty($row['porta_consultada'])) {
                        $link_params['ip_publico'] = $row['ip_consultado'];
                        $link_params['porta'] = $row['porta_consultada'];
                    } elseif (!empty($row['ipv6_cliente'])) {
                        $link_params['ipv6_busca'] = $row['ipv6_cliente'];
                    }
                    $link_params['data_inicio'] = date('Y-m-d', strtotime($row['data_consulta']));
                    $link_params['data_fim'] = date('Y-m-d', strtotime($row['data_consulta']));
                    $link_params['motivo'] = 'Reabertura de consulta';
                    $link_params['protocolo'] = $row['protocolo_judicial'] ?? '';
                    
                    $link = 'consultar.php?' . http_build_query($link_params);
                ?>
                <tr>
                    <td><?php echo date('d/m/Y H:i', strtotime($row['data_consulta'])); ?></td>
                    <td><?php echo htmlspecialchars($row['usuario']); ?></td>
                    <td>
                        <?php if (!empty($row['ip_consultado'])): ?>
                            <strong><?php echo htmlspecialchars($row['ip_consultado']); ?></strong>
                        <?php else: ?>
                            <span class="text-muted">-</span>
                        <?php endif; ?>
                    </td>
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
                    <td>
                        <a href="<?php echo $link; ?>" class="btn-sm">🔍 Reabrir</a>
                    </td>
                </tr>
                <?php endforeach; else: ?>
                <tr><td colspan="9" style="text-align:center;color:#999;">Nenhuma consulta</td></tr>
                <?php endif; ?>
            </tbody>
        </table>
    </div>
</body>
</html>
RELATORIOS_PHP

# 12.11 ADMIN.PHP
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

print_success "TODOS os 11 arquivos PHP criados com sucesso!"

# ============================================================
# 12.12 ADICIONAR HEADERS EM TODOS OS ARQUIVOS PHP
# ============================================================
print_header "12.12. ADICIONANDO HEADERS ANTI-CACHE"

for arquivo in /var/www/html/cgnat/{index,dashboard,consultar,relatorios,login,admin,auth,functions}.php; do
    if [ -f "$arquivo" ]; then
        if ! grep -q "require_once 'headers.php';" "$arquivo"; then
            sed -i 's/^<?php/<?php\nrequire_once '\''headers.php'\'';/' "$arquivo"
            print_info "Headers adicionado em $(basename $arquivo)"
        fi
    fi
done

print_success "Headers anti-cache adicionados em todos os arquivos PHP"

# ============================================================
# 13. CONFIGURAR RSYSLOG (COM OTIMIZAÇÕES)
# ============================================================
print_header "13. CONFIGURANDO RSYSLOG"

# Garantir que o diretório existe
mkdir -p /var/run/cgnat
chmod 755 /var/run/cgnat

# Criar pipe
mkfifo /var/run/cgnat.pipe 2>/dev/null || true
chmod 666 /var/run/cgnat.pipe 2>/dev/null || true

cat > /etc/rsyslog.d/99-cgnat.conf << 'RSYSLOG'
# Otimizações para alta velocidade
$MaxMessageSize 64k
$IMUDPServerTimeStamp on
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

# Criar script de inicialização para o RAM disk
mkdir -p /dev/shm/cgnat_logs
chmod 755 /dev/shm/cgnat_logs

cat > /etc/systemd/system/cgnat-ramdisk.service << 'EOF'
[Unit]
Description=CGNAT RAM Disk for logs
Before=rsyslog.service

[Service]
Type=oneshot
ExecStart=/bin/bash -c 'mkdir -p /dev/shm/cgnat_logs && chmod 755 /dev/shm/cgnat_logs'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cgnat-ramdisk.service

# Mover raw.log para RAM se existir
if [ -f /var/log/cgnat/raw.log ]; then
    mv /var/log/cgnat/raw.log /dev/shm/cgnat_logs/ 2>/dev/null || true
fi
ln -sf /dev/shm/cgnat_logs/raw.log /var/log/cgnat/raw.log
chown syslog:adm /dev/shm/cgnat_logs/raw.log 2>/dev/null || true
chmod 640 /dev/shm/cgnat_logs/raw.log 2>/dev/null || true

systemctl restart rsyslog 2>/dev/null || true
print_success "Rsyslog configurado com otimizações e raw.log em RAM"

# ============================================================
# 14. CONFIGURAR CRONJOBS
# ============================================================
print_header "14. CONFIGURANDO CRONJOBS"

cat > /tmp/crontab_cgnat << 'CRON'
0 2 * * * /usr/local/bin/backup_cgnat.sh >> /var/log/cgnat/backup.log 2>&1
*/2 * * * * /usr/local/bin/sync_mkauth.sh >> /var/log/cgnat/sync_mkauth.log 2>&1
25 0 25 * * /usr/local/bin/create_cgnat_partition.sh >> /var/log/cgnat/partition_create.log 2>&1
0 8 * * * /usr/local/bin/monitor_disco.sh >> /var/log/cgnat/disco.log 2>&1
CRON

crontab /tmp/crontab_cgnat 2>/dev/null || true
rm /tmp/crontab_cgnat

print_success "Cronjobs configurados"

# ============================================================
# 15. CRIAR SCRIPTS ÚTEIS (COM sync_mkauth.sh CORRIGIDO - MANTÉM IPv6)
# ============================================================
print_header "15. CRIANDO SCRIPTS ÚTEIS"

# Script de Backup
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
MONITOR
chmod +x /usr/local/bin/monitor_disco.sh

# Script para criar partições automaticamente
cat > /usr/local/bin/create_cgnat_partition.sh << 'PART'
#!/bin/bash
# Script para criar partições CGNAT automaticamente

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
        
        IF NOT EXISTS (
            SELECT 1 FROM pg_tables 
            WHERE tablename = nome_particao
        ) THEN
            EXECUTE format('
                CREATE TABLE %I PARTITION OF cgnat_logs
                FOR VALUES FROM (%L) TO (%L)
            ', nome_particao, data_inicio, data_fim);
            
            EXECUTE format('
                CREATE INDEX %I ON %I(ip_publico)
            ', 'idx_' || nome_particao || '_ip_pub', nome_particao);
            
            EXECUTE format('
                CREATE INDEX %I ON %I(ip_privado)
            ', 'idx_' || nome_particao || '_ip_priv', nome_particao);
            
            EXECUTE format('
                CREATE INDEX %I ON %I(data_hora)
            ', 'idx_' || nome_particao || '_data', nome_particao);
            
            RAISE NOTICE 'Partição % criada com sucesso', nome_particao;
        END IF;
    END LOOP;
END $$;
SQL

echo "$(date): Partições criadas com sucesso."
PART
chmod +x /usr/local/bin/create_cgnat_partition.sh

# Script de Sincronização MK-AUTH (MANTENDO O PADRÃO QUE FUNCIONA)
cat > /usr/local/bin/sync_mkauth.sh << EOF
#!/bin/bash
# Script para sincronizar dados do MK-AUTH via SSH
# Mantém os campos ipv6_prefix, ipv6_address e ipv6_atualizado

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
    
    -- Atualizar apenas os campos que vêm do MK-AUTH
    -- Mantendo ipv6_prefix, ipv6_address e ipv6_atualizado
    UPDATE clientes c
    SET 
        nome = t.nome,
        ip_privado = t.ip_privado::inet
    FROM temp_clientes t
    WHERE c.login = t.login;
    
    -- Inserir novos clientes (que não existem)
    INSERT INTO clientes (login, nome, ip_privado)
    SELECT 
        t.login,
        t.nome,
        t.ip_privado::inet
    FROM temp_clientes t
    LEFT JOIN clientes c ON t.login = c.login
    WHERE c.login IS NULL;
    
    -- Remover clientes que não estão mais no MK-AUTH
    DELETE FROM clientes 
    WHERE login NOT IN (SELECT login FROM temp_clientes);
    
    SELECT 'Clientes sincronizados: ' || COUNT(*) as status FROM clientes;
SQL
    
    rm -f "\${TMP_FILE}"
else
    echo "ERRO: Não foi possível exportar dados do MK-AUTH"
fi

echo "\$(date): Sincronização concluída."
EOF
chmod +x /usr/local/bin/sync_mkauth.sh

# ============================================================
# 15.5. EXECUTAR SINCRONIZAÇÃO INICIAL
# ============================================================
print_header "15.5. EXECUTANDO SINCRONIZAÇÃO INICIAL"

print_info "Populando tabela clientes com dados do MK-AUTH..."
/usr/local/bin/sync_mkauth.sh

if [ $? -eq 0 ]; then
    print_success "Sincronização inicial concluída com sucesso!"
    
    # Mostrar quantos clientes foram importados
    TOTAL_CLIENTES=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM clientes;" | xargs)
    print_info "Total de clientes importados: ${TOTAL_CLIENTES}"
else
    print_warning "Sincronização inicial falhou. Execute manualmente após a instalação:"
    print_info "/usr/local/bin/sync_mkauth.sh"
fi

print_success "Sincronização inicial finalizada"

# ============================================================
# 15.6. CRIAR SCRIPT DE SINCRONIZAÇÃO IPv6
# ============================================================
print_header "15.6. CRIANDO SCRIPT DE SINCRONIZAÇÃO IPv6"

cat > /usr/local/bin/sync_ipv6_cisco.sh << EOF
#!/bin/bash
# Script para sincronizar IPv6 do Cisco ASR com a tabela clientes

echo "\$(date): Iniciando sincronização IPv6 do Cisco..."
echo "⏳ Aguarde, estamos sincronizando os dados com o Cisco..."

# Usando as variáveis do script principal
CISCO_IP="${CISCO_IP}"
CISCO_USER="${CISCO_USER}"
CISCO_PASS="${CISCO_PASS}"
TMP_FILE="/tmp/ipv6_binding_\$\$.txt"

# Coletar dados do Cisco
sshpass -p "\$CISCO_PASS" ssh \
    -o KexAlgorithms=+diffie-hellman-group14-sha1 \
    -o HostKeyAlgorithms=+ssh-rsa \
    -o PubkeyAcceptedAlgorithms=+ssh-rsa \
    -o StrictHostKeyChecking=no \
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
    # Remove espaços no início e no final
    line=\$(echo "\$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//' | tr -d '\r')
    
    # Se encontrar "Username :"
    if echo "\$line" | grep -q "^Username :"; then
        login=\$(echo "\$line" | sed 's/^Username : //' | tr -d '\r')
    fi
    
    # Se encontrar "Prefix:"
    if echo "\$line" | grep -q "^Prefix:"; then
        prefix=\$(echo "\$line" | sed 's/^Prefix: //' | awk '{print \$1}' | tr -d '\r')
        
        if [ ! -z "\$login" ] && [ ! -z "\$prefix" ]; then
            # Supressão do output do PostgreSQL
            sudo -u postgres psql -d cgnat_logs -q << PSQL 2>/dev/null
UPDATE clientes 
SET ipv6_prefix = '\$prefix',
    ipv6_atualizado = NOW()
WHERE login = '\$login';
PSQL
            if [ \$? -eq 0 ]; then
                UPDATED=\$((UPDATED + 1))
            fi
        fi
    fi
done < "\$TMP_FILE"

echo "✅ Sincronização IPv6 concluída. Clientes atualizados: \$UPDATED"
rm -f "\$TMP_FILE"
EOF

chmod +x /usr/local/bin/sync_ipv6_cisco.sh
print_success "Script de sincronização IPv6 criado"

# ============================================================
# 15.6.1. EXECUTAR SINCRONIZAÇÃO IPv6 INICIAL
# ============================================================
print_header "15.6.1. EXECUTANDO SINCRONIZAÇÃO IPv6 INICIAL"

print_info "Coletando IPv6 dos clientes no Cisco ASR..."

# Marcar tempo de início
INICIO=$(date +%s)

echo ""
echo "⏳ Aguardando sincronização com o Cisco ASR..."
echo "📡 Conectando ao Cisco ASR em ${CISCO_IP}..."
echo ""

# Função para mostrar barra de progresso
mostrar_progresso() {
    local atual=$1
    local total=$2
    local tamanho=50
    local progresso=$((atual * tamanho / total))
    local restante=$((tamanho - progresso))
    
    # Construir a barra
    local barra=""
    for ((i=0; i<progresso; i++)); do
        barra="${barra}█"
    done
    for ((i=0; i<restante; i++)); do
        barra="${barra}░"
    done
    
    printf "\r   [%s] %3d%% (%d/%d)" "$barra" $((atual * 100 / total)) $atual $total
}

# Iniciar sincronização em background
/usr/local/bin/sync_ipv6_cisco.sh &
PID=$!

# Estimar total de clientes
TOTAL_CLIENTES=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM clientes;" 2>/dev/null | xargs)
TOTAL_CLIENTES=${TOTAL_CLIENTES:-629}

# Barra de progresso
ATUAL=0
echo ""
echo "📊 Progresso da sincronização:"
echo ""

while kill -0 $PID 2>/dev/null; do
    # Buscar quantos clientes já foram atualizados
    ATUAL=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM clientes WHERE ipv6_atualizado IS NOT NULL AND ipv6_atualizado > NOW() - INTERVAL '5 minutes';" 2>/dev/null | xargs)
    ATUAL=${ATUAL:-0}
    
    # Limitar ao total
    if [ $ATUAL -gt $TOTAL_CLIENTES ]; then
        ATUAL=$TOTAL_CLIENTES
    fi
    
    # Mostrar barra de progresso (atualiza a linha)
    mostrar_progresso $ATUAL $TOTAL_CLIENTES
    
    sleep 2
done

# Aguardar finalização
wait $PID
STATUS=$?

# Finalizar barra com 100%
echo ""
mostrar_progresso $TOTAL_CLIENTES $TOTAL_CLIENTES
echo ""
echo ""

# Calcular tempo final
FIM=$(date +%s)
DURACAO=$((FIM - INICIO))
MINUTOS=$((DURACAO / 60))
SEGUNDOS=$((DURACAO % 60))

# Buscar total de clientes com IPv6
TOTAL_IPV6=$(sudo -u postgres psql -d cgnat_logs -t -c "SELECT COUNT(*) FROM clientes WHERE ipv6_prefix IS NOT NULL;" 2>/dev/null | xargs)

if [ $STATUS -eq 0 ]; then
    echo "✅ Sincronização IPv6 concluída em ${MINUTOS}m${SEGUNDOS}s!"
    echo "   📊 Total de clientes com IPv6: ${TOTAL_IPV6:-0} de ${TOTAL_CLIENTES}"
    print_success "Sincronização IPv6 inicial finalizada"
else
    echo "❌ Sincronização IPv6 inicial falhou em ${MINUTOS}m${SEGUNDOS}s"
    print_warning "Sincronização IPv6 inicial falhou. O cron tentará novamente a cada 5 minutos."
    print_info "Você pode executar manualmente: /usr/local/bin/sync_ipv6_cisco.sh"
fi

# ============================================================
# 15.7. CONFIGURAR CRON PARA IPv6
# ============================================================
print_header "15.7. CONFIGURANDO CRON PARA IPv6"

(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/sync_ipv6_cisco.sh >> /var/log/cgnat/sync_ipv6.log 2>&1") | crontab -
print_success "Cron para IPv6 configurado (a cada 5 minutos)"

# ============================================================
# 15.8. APLICAR OTIMIZAÇÕES POSTGRESQL
# ============================================================
print_header "15.8. APLICANDO OTIMIZAÇÕES POSTGRESQL"

print_info "Aplicando otimizações para reduzir escrita em disco..."

sudo -u postgres psql -d cgnat_logs << 'SQL'
-- Ativar compressão WAL (reduz 30-50% do espaço)
ALTER SYSTEM SET wal_compression = on;

-- Checkpoints menos frequentes (reduz I/O)
ALTER SYSTEM SET checkpoint_timeout = '15min';

-- Limitar tamanho do WAL
ALTER SYSTEM SET max_wal_size = '2GB';
ALTER SYSTEM SET min_wal_size = '512MB';

-- Reduzir escritas síncronas (CUIDADO! Risco de perda de dados em crash)
-- Mantenha UPS e backups em dia
ALTER SYSTEM SET synchronous_commit = off;
ALTER SYSTEM SET wal_sync_method = fdatasync;

-- Recarregar configuração
SELECT pg_reload_conf();

-- Mostrar configurações aplicadas
SELECT name, setting 
FROM pg_settings 
WHERE name IN ('wal_compression', 'checkpoint_timeout', 'max_wal_size', 'min_wal_size', 'synchronous_commit', 'wal_sync_method');
SQL

print_success "Otimizações PostgreSQL aplicadas"

print_info "⚠️  synchronous_commit = off foi ativado!"
print_info "   Isso reduz 50-70% da escrita em disco."
print_info "   Em caso de queda de energia, você pode perder até 1 segundo de dados."
print_info "   Mantenha o UPS e backups em dia!"

# ============================================================
# 16. CONCEDER PERMISSÃO USUARIO CGNAT-PARSER
# ============================================================
sudo -u postgres psql -d cgnat_logs << 'EOF'
-- Conceder permissões na tabela pppoe_sessoes
GRANT ALL PRIVILEGES ON TABLE pppoe_sessoes TO cgnat_parser;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO cgnat_parser;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO cgnat_parser;

-- Verificar permissões
\dp pppoe_sessoes
EOF

# Reiniciar o parser
sudo systemctl restart cgnat-parser

# ============================================================
# 17. REDIRECIONAR RAIZ PARA /CGNAT/
# ============================================================
print_header "16. CONFIGURANDO REDIRECIONAMENTO"

mv /var/www/html/index.html /var/www/html/index2.html 2>/dev/null || true

cat > /var/www/html/index.php << 'EOF'
<?php
header('Location: /cgnat/login.php');
exit;
?>
EOF

chown www-data:www-data /var/www/html/index.php
chmod 644 /var/www/html/index.php
systemctl restart apache2 2>/dev/null || true

print_success "Redirecionamento configurado"

# ============================================================
# 18. PERMISSÕES FINAIS
# ============================================================
print_header "17. AJUSTANDO PERMISSÕES FINAIS"

chown -R www-data:www-data /var/www/html/cgnat/ 2>/dev/null || true
chmod -R 755 /var/www/html/cgnat/ 2>/dev/null || true
chmod 644 /var/www/html/cgnat/*.php 2>/dev/null || true
systemctl restart apache2 2>/dev/null || true

print_success "Permissões ajustadas"

# ============================================================
# 19. RESULTADO FINAL
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
echo "   PostgreSQL: systemctl status postgresql"
echo "   Rsyslog: systemctl status rsyslog"
echo "   Parser: systemctl status cgnat-parser"
echo "   Apache: systemctl status apache2"
echo ""
echo "📊 PRÓXIMOS PASSOS:"
echo "   1. Acesse a interface web: http://$IP/"
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
