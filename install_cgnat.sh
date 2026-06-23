#!/bin/bash
# ============================================================
# SCRIPT DE INSTALAÇÃO - SISTEMA CGNAT LGPD
# ============================================================
# Versão: 1.0 - Debian 12 x64
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
CISCO_IP="190.196.243.250"
CISCO_USER="mkauth"
CISCO_PASS="Wbt@07717125"
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
    sudo \
    wget curl vim htop net-tools \
    build-essential \
    python3 python3-pip python3-venv \
    postgresql postgresql-contrib \
    rsyslog logrotate \
    apache2 php php-pgsql php-curl php-json php-mbstring \
    sshpass \
    default-mysql-client \
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

chown -R www-data:www-data /var/www/html/cgnat 2>/dev/null || true
chown -R root:root /opt/cgnat 2>/dev/null || true
chown -R root:root /var/log/cgnat 2>/dev/null || true
chown -R postgres:postgres /backup/cgnat 2>/dev/null || true
chmod -R 755 /opt/cgnat /var/www/html/cgnat /var/log/cgnat 2>/dev/null || true

print_success "Diretórios criados"

# ============================================================
# 6. CONFIGURAR POSTGRESQL
# ============================================================
print_header "6. CONFIGURANDO POSTGRESQL"

systemctl stop postgresql 2>/dev/null || true
systemctl stop postgresql@15-main 2>/dev/null || true

pg_dropcluster 15 main --stop 2>/dev/null || true
rm -rf /var/lib/postgresql/15/main 2>/dev/null || true
rm -f /var/run/postgresql/.s.PGSQL.5432 2>/dev/null || true
rm -f /var/run/postgresql/.s.PGSQL.5432.lock 2>/dev/null || true

pg_createcluster 15 main --start -u postgres
systemctl start postgresql
systemctl enable postgresql
sleep 3

if ! systemctl is-active --quiet postgresql; then
    pg_ctlcluster 15 main start
    sleep 3
fi

if ! systemctl is-active --quiet postgresql; then
    print_error "Não foi possível iniciar o PostgreSQL"
    pg_lsclusters
    journalctl -u postgresql -n 10 --no-pager
    exit 1
fi

print_success "PostgreSQL rodando"

if ! sudo -u postgres psql -c "SELECT 1" 2>/dev/null; then
    print_error "PostgreSQL não responde"
    exit 1
fi

print_success "PostgreSQL configurado"

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
# 8. CRIAR TABELAS (COM AS NOVAS COLUNAS PARA LGPD)
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

CREATE INDEX IF NOT EXISTS idx_cgnat_ip_publico ON cgnat_logs(ip_publico);
CREATE INDEX IF NOT EXISTS idx_cgnat_ip_privado ON cgnat_logs(ip_privado);
CREATE INDEX IF NOT EXISTS idx_cgnat_data_hora ON cgnat_logs(data_hora);
CREATE INDEX IF NOT EXISTS idx_cgnat_ip_porta_data ON cgnat_logs(ip_publico, porta_publica, data_hora);
CREATE INDEX IF NOT EXISTS idx_cgnat_acao ON cgnat_logs(acao);
CREATE INDEX IF NOT EXISTS idx_cgnat_login ON cgnat_logs(login);
CREATE INDEX IF NOT EXISTS idx_clientes_ip_privado ON clientes(ip_privado);
CREATE INDEX IF NOT EXISTS idx_clientes_login ON clientes(login);
CREATE INDEX IF NOT EXISTS idx_lgpd_data ON lgpd_audit(data_consulta);
CREATE INDEX IF NOT EXISTS idx_lgpd_ip_publico ON lgpd_audit(ip_consultado);
CREATE INDEX IF NOT EXISTS idx_lgpd_ip_privado ON lgpd_audit(ip_privado);
CREATE INDEX IF NOT EXISTS idx_lgpd_cliente ON lgpd_audit(cliente_nome);
CREATE INDEX IF NOT EXISTS idx_usuarios_usuario ON usuarios(usuario);

INSERT INTO usuarios (usuario, senha_hash, nome_completo, perfil) VALUES
('admin', '$2y$10$WmuK/dyBnXHzG/iv9cB50uufL3FFKivItk9/rlT3YuliO0CAo30nq', 'Administrador', 'admin'),
('juridico', '$2y$10$WmuK/dyBnXHzG/iv9cB50uufL3FFKivItk9/rlT3YuliO0CAo30nq', 'Departamento Jurídico', 'juridico'),
('operador', '$2y$10$WmuK/dyBnXHzG/iv9cB50uufL3FFKivItk9/rlT3YuliO0CAo30nq', 'Operador', 'operador')
ON CONFLICT (usuario) DO NOTHING;

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

GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO cgnat_admin;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO cgnat_admin;
GRANT INSERT ON cgnat_logs TO cgnat_parser;
GRANT INSERT ON clientes TO cgnat_parser;
EOF

print_success "Tabelas criadas com as novas colunas LGPD"

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
# 10. CRIAR O PARSER PYTHON
# ============================================================
print_header "10. CRIANDO PARSER PYTHON"

cat > /opt/cgnat/cgnat_parser.py << 'EOF'
#!/usr/bin/env python3
# /opt/cgnat/cgnat_parser.py - CORRIGIDO (busca primeiro em clientes)

import re
import sys
import psycopg2
from datetime import datetime
import logging
from typing import Dict, Optional, Tuple

# Configurar logging
logging.basicConfig(
    filename='/var/log/cgnat/parser.log',
    level=logging.INFO,
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
        self.stats = {
            'created': 0,
            'deleted': 0,
            'errors': 0,
            'found_in_clientes': 0,
            'found_in_pppoe': 0,
            'not_found': 0
        }
        
    def parse_log_line(self, line: str) -> Optional[Dict]:
        # Extrai timestamp
        timestamp_match = re.search(r'(\w{3}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2}\.\d{3})', line)
        if timestamp_match:
            data_hora = self.parse_cisco_timestamp(timestamp_match.group(1))
        else:
            data_hora = datetime.now()
        
        # Extrai a mensagem NAT
        nat_match = re.search(r'%NAT-6-LOG_TRANSLATION:\s+(.+)', line)
        if not nat_match:
            return None
            
        nat_message = nat_match.group(1)
        
        # Padrão para Created/Deleted Translation
        pattern = r'(Created|Deleted)\s+Translation\s+(\w+)\s+([\d.]+):(\d+)\s+([\d.]+):(\d+)\s+([\d.]+):(\d+)\s+([\d.]+):(\d+)\s+(\d+)'
        match = re.search(pattern, nat_message)
        
        if not match:
            logging.warning(f"NAT message não parseada: {nat_message}")
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
        except Exception as e:
            logging.error(f"Erro ao parsear timestamp {timestamp_str}: {e}")
            return datetime.now()
    
    def get_pppoe_login(self, ip_privado: str, data_hora: datetime) -> Tuple[Optional[str], Optional[int]]:
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
                logging.debug(f"Login encontrado em clientes: {result[0]} para IP {ip_privado}")
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
                logging.debug(f"Login encontrado em pppoe_sessoes: {result[0]} para IP {ip_privado}")
                return result[0], result[1]
            
            # Não encontrou em lugar nenhum
            self.stats['not_found'] += 1
            if self.stats['not_found'] % 1000 == 0:
                logging.warning(f"IP {ip_privado} não encontrado em nenhuma tabela ({self.stats['not_found']} total)")
            return None, None
            
        except Exception as e:
            logging.error(f"Erro ao buscar login para IP {ip_privado}: {e}")
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
            logging.error(f"Erro ao salvar log: {e}")
            self.conn.rollback()
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
            logging.error(f"Erro ao processar linha: {e}")
            self.stats['errors'] += 1
    
    def run(self):
        logging.info("Parser CGNAT iniciado - CORRIGIDO (busca em clientes primeiro)")
        
        for line in sys.stdin:
            line = line.strip()
            if not line or '%NAT-6-LOG_TRANSLATION' not in line:
                continue
            self.process_line(line)
            
            if (self.stats['created'] + self.stats['deleted']) % 1000 == 0:
                logging.info(f"Stats: Created={self.stats['created']}, Deleted={self.stats['deleted']}, "
                           f"Found in clientes={self.stats['found_in_clientes']}, "
                           f"Found in pppoe={self.stats['found_in_pppoe']}, "
                           f"Not found={self.stats['not_found']}, Errors={self.stats['errors']}")

if __name__ == "__main__":
    parser = CGNATParserASR()
    parser.run()
EOF

chmod +x /opt/cgnat/cgnat_parser.py
print_success "Parser Python criado com correções"

# ============================================================
# 11. CRIAR SERVICE DO PARSER (CORRIGIDO)
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

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable cgnat-parser
systemctl start cgnat-parser

print_success "Service do parser criado"

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

# 12.7 INDEX.PHP
cat > /var/www/html/cgnat/index.php << 'INDEX_PHP'
<?php
require_once 'auth.php';
verificarPermissao();
require_once 'functions.php';

$db = getDBConnection();

$stmt = $db->query("SELECT COUNT(*) FROM cgnat_logs");
$total_logs = $stmt->fetchColumn();

$stmt = $db->query("SELECT COUNT(*) FROM clientes");
$total_clientes = $stmt->fetchColumn();

$stmt = $db->query("SELECT COUNT(*) FROM lgpd_audit WHERE DATE(data_consulta) = CURRENT_DATE");
$consultas_hoje = $stmt->fetchColumn();

include 'menu.php';
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>CGNAT LGPD - Início</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #f5f5f5;
            padding: 20px;
        }
        .container {
            max-width: 1200px;
            margin: 0 auto;
        }
        .card-welcome {
            background: white;
            border-radius: 10px;
            padding: 40px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }
        .card-welcome h1 {
            color: #333;
            font-size: 28px;
            margin-bottom: 10px;
        }
        .card-welcome p {
            color: #666;
            font-size: 16px;
        }
        .card-welcome .user {
            color: #667eea;
            font-weight: bold;
        }
        .cards {
            display: grid;
            grid-template-columns: repeat(4, 1fr);
            gap: 20px;
            margin-bottom: 30px;
        }
        .card {
            background: white;
            padding: 25px;
            border-radius: 10px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            text-align: center;
        }
        .card .numero {
            font-size: 32px;
            font-weight: bold;
            color: #667eea;
        }
        .card .label {
            color: #888;
            margin-top: 5px;
            font-size: 14px;
        }
        .card-verde .numero { color: #27ae60; }
        .card-vermelho .numero { color: #e74c3c; }
        .card-amarelo .numero { color: #f39c12; }
        .btn-consulta {
            display: inline-block;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 18px 50px;
            border-radius: 8px;
            font-size: 18px;
            font-weight: 600;
            cursor: pointer;
            text-decoration: none;
            transition: transform 0.2s;
            margin-top: 10px;
        }
        .btn-consulta:hover {
            transform: scale(1.02);
        }
        .actions {
            text-align: center;
            margin-top: 20px;
        }
        @media (max-width: 768px) {
            .cards {
                grid-template-columns: 1fr 1fr;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="card-welcome">
            <h1>👋 Bem-vindo, <span class="user"><?php echo htmlspecialchars($_SESSION['nome_completo']); ?></span></h1>
            <p>Sistema de Consulta CGNAT para atendimento à LGPD.</p>
            <p style="margin-top: 5px; font-size: 14px; color: #999;">
                Perfil: <strong><?php echo htmlspecialchars($_SESSION['perfil']); ?></strong>
            </p>
        </div>
        
        <div class="cards">
            <div class="card card-verde">
                <div class="numero"><?php echo $consultas_hoje; ?></div>
                <div class="label">Consultas Hoje</div>
            </div>
            <div class="card">
                <div class="numero"><?php echo number_format($total_logs); ?></div>
                <div class="label">Total de Logs CGNAT</div>
            </div>
            <div class="card card-amarelo">
                <div class="numero"><?php echo number_format($total_clientes); ?></div>
                <div class="label">Clientes Cadastrados</div>
            </div>
            <div class="card card-vermelho">
                <div class="numero"><?php echo date('d/m/Y'); ?></div>
                <div class="label">Data Atual</div>
            </div>
        </div>
        
        <div class="actions">
            <a href="consultar.php" class="btn-consulta">🔍 Ir para Consultas</a>
        </div>
    </div>
</body>
</html>
INDEX_PHP

# 12.8 DASHBOARD.PHP
cat > /var/www/html/cgnat/dashboard.php << 'DASHBOARD_PHP'
<?php
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

        /* TABELA - TAMANHO ORIGINAL */
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
            <div class="card card-vermelho"><div class="numero"><?php echo number_format($total_logs); ?></div><div class="label">Total Logs CGNAT</div></div>
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
                            <th>Log Original</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php if ($ultimas): ?>
                            <?php foreach ($ultimas as $row): ?>
                            <tr>
                                <td style="white-space:nowrap;"><?php echo date('d/m/Y H:i', strtotime($row['data_consulta'])); ?></td>
                                <td><?php echo htmlspecialchars($row['usuario']); ?></td>
                                <td><strong><?php echo htmlspecialchars($row['ip_consultado']); ?></strong></td>
                                <td><?php echo htmlspecialchars($row['porta_consultada']); ?></td>
                                <td>
                                    <?php if (!empty($row['cliente_nome'])): ?>
                                        <span class="badge-info"><?php echo htmlspecialchars($row['cliente_nome']); ?></span>
                                    <?php else: ?>
                                        <span class="text-muted">-</span>
                                    <?php endif; ?>
                                </td>
                                <td><?php echo htmlspecialchars($row['ip_privado'] ?? '-'); ?></td>
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
                            <tr><td colspan="7" style="text-align:center;color:#999;padding:20px;">Nenhuma consulta realizada</td></tr>
                        <?php endif; ?>
                    </tbody>
                </table>
            </div>
        </div>
    </div>
</body>
</html>
DASHBOARD_PHP

# 12.9 CONSULTAR.PHP
cat > /var/www/html/cgnat/consultar.php << 'CONSULTAR_PHP'
<?php
require_once 'auth.php';
verificarPermissao();
require_once 'functions.php';

$resultados = null;
$total = 0;
$mensagem = '';
$cliente_nome = '';
$ip_privado = '';
$log_data_hora = '';
$log_acao = '';
$log_destino = '';
$log_protocolo = '';

// Verificar se veio via GET (reabrir consulta)
if ($_SERVER['REQUEST_METHOD'] === 'GET' && isset($_GET['ip_publico']) && isset($_GET['porta'])) {
    $_POST['ip_publico'] = $_GET['ip_publico'];
    $_POST['porta'] = $_GET['porta'];
    $_POST['data_inicio'] = $_GET['data_inicio'] ?? date('Y-m-d');
    $_POST['data_fim'] = $_GET['data_fim'] ?? date('Y-m-d');
    $_POST['hora_inicio'] = $_GET['hora_inicio'] ?? '00:00';
    $_POST['hora_fim'] = $_GET['hora_fim'] ?? '23:59';
    $_POST['motivo'] = $_GET['motivo'] ?? 'Reabertura de consulta';
    $_POST['protocolo'] = $_GET['protocolo'] ?? '';
    
    $_SERVER['REQUEST_METHOD'] = 'POST';
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $ip_publico = $_POST['ip_publico'] ?? '';
    $porta = $_POST['porta'] ?? '';
    $data_inicio = $_POST['data_inicio'] . ' ' . ($_POST['hora_inicio'] ?? '00:00:00');
    $data_fim = $_POST['data_fim'] . ' ' . ($_POST['hora_fim'] ?? '23:59:59');
    $motivo = $_POST['motivo'] ?? 'Consulta LGPD';
    $protocolo = $_POST['protocolo'] ?? '';
    
    if ($ip_publico && $porta) {
        try {
            $db = getDBConnection();
            
            // CONSULTA COM JOIN PARA PEGAR O NOME DO CLIENTE
            $stmt = $db->prepare("
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
                    c.login as cliente_login
                FROM cgnat_logs c
                LEFT JOIN clientes cl ON c.login = cl.login
                WHERE c.ip_publico = ?::inet
                AND c.porta_publica = ?
                AND c.data_hora BETWEEN ? AND ?
                ORDER BY c.data_hora DESC
                LIMIT 1000
            ");
            $stmt->execute([$ip_publico, $porta, $data_inicio, $data_fim]);
            $resultados = $stmt->fetchAll(PDO::FETCH_ASSOC);
            $total = count($resultados);
            
            // Pegar informações do primeiro resultado
            if ($total > 0) {
                $primeiro = $resultados[0];
                $cliente_nome = $primeiro['cliente_nome'] ?? 'Nao identificado';
                $ip_privado = $primeiro['ip_privado'] ?? null;
                $log_data_hora = $primeiro['data_hora'] ?? null;
                $log_acao = $primeiro['acao'] ?? null;
                $log_destino = ($primeiro['ip_destino'] ?? '') . ':' . ($primeiro['porta_destino'] ?? '');
                $log_protocolo = $primeiro['protocolo'] ?? null;
            }
            
            // CORREÇÃO: Tratar valores vazios para campos INET
            $ip_privado_sql = (!empty($ip_privado) && $ip_privado != '') ? $ip_privado : null;
            $ip_origem = (!empty($_SERVER['REMOTE_ADDR'])) ? $_SERVER['REMOTE_ADDR'] : null;
            
            // SALVAR NA TABELA lgpd_audit COM TODAS AS INFORMAÇÕES
            $stmt = $db->prepare("
                INSERT INTO lgpd_audit (
                    usuario, 
                    ip_consultado, 
                    porta_consultada, 
                    motivo, 
                    protocolo_judicial,
                    ip_privado,
                    cliente_nome,
                    log_data_hora,
                    log_acao,
                    log_destino,
                    log_protocolo,
                    resultado_registros,
                    ip_origem_consulta,
                    user_agent
                ) VALUES (?, ?, ?, ?, ?, ?::inet, ?, ?, ?, ?, ?, ?, ?::inet, ?)
            ");
            $stmt->execute([
                $_SESSION['usuario'],
                $ip_publico,
                $porta,
                $motivo,
                $protocolo,
                $ip_privado_sql,  // PODE SER NULL
                $cliente_nome,
                $log_data_hora,
                $log_acao,
                $log_destino,
                $log_protocolo,
                $total,
                $ip_origem,       // PODE SER NULL
                $_SERVER['HTTP_USER_AGENT'] ?? null
            ]);
            
            $mensagem = $total > 0 ? "✅ Encontrados {$total} registros." : '⚠️ Nenhum registro encontrado.';
            
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
        .alert { padding: 15px; border-radius: 8px; margin-bottom: 20px; }
        .alert-success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .alert-danger { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .alert-warning { background: #fff3cd; color: #856404; border: 1px solid #ffeeba; }
        .client-info { background: #e7f3ff; padding: 15px; border-radius: 8px; margin: 15px 0; border-left: 4px solid #667eea; }
        .client-info h3 { color: #004085; margin: 0; }
        .text-muted { color: #999; }
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
            <p style="margin-top:5px;color:#555;font-size:14px;">
                📍 IP Privado: <strong><?php echo htmlspecialchars($ip_privado); ?></strong>
            </p>
            <?php endif; ?>
        </div>
        <?php endif; ?>
        
        <form method="POST" id="formConsulta">
            <div class="row">
                <div class="form-group">
                    <label>IP Público *</label>
                    <input type="text" name="ip_publico" id="ip_publico" placeholder="Ex: 190.196.242.18" required value="<?php echo $_POST['ip_publico'] ?? ''; ?>">
                </div>
                <div class="form-group">
                    <label>Porta Pública *</label>
                    <input type="number" name="porta" id="porta" placeholder="Ex: 51478" required value="<?php echo $_POST['porta'] ?? ''; ?>">
                </div>
            </div>
            <div class="row">
                <div class="form-group">
                    <label>Data Início</label>
                    <input type="date" name="data_inicio" id="data_inicio" value="<?php echo $_POST['data_inicio'] ?? date('Y-m-d'); ?>">
                </div>
                <div class="form-group">
                    <label>Data Fim</label>
                    <input type="date" name="data_fim" id="data_fim" value="<?php echo $_POST['data_fim'] ?? date('Y-m-d'); ?>">
                </div>
            </div>
            <div class="row">
                <div class="form-group">
                    <label>Hora Início</label>
                    <input type="time" name="hora_inicio" id="hora_inicio" value="<?php echo $_POST['hora_inicio'] ?? '00:00'; ?>">
                </div>
                <div class="form-group">
                    <label>Hora Fim</label>
                    <input type="time" name="hora_fim" id="hora_fim" value="<?php echo $_POST['hora_fim'] ?? '23:59'; ?>">
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
                    </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
        </div>
        <?php endif; ?>
    </div>
    
    <script>
    function limparFormulario() {
        document.getElementById('ip_publico').value = '';
        document.getElementById('porta').value = '';
        document.getElementById('protocolo').value = '';
        
        var hoje = new Date().toISOString().split('T')[0];
        document.getElementById('data_inicio').value = hoje;
        document.getElementById('data_fim').value = hoje;
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
    
    $stmt = $db->prepare("SELECT id, usuario, ip_consultado, porta_consultada, motivo, protocolo_judicial, data_consulta FROM lgpd_audit WHERE DATE(data_consulta) BETWEEN ? AND ? ORDER BY data_consulta DESC LIMIT 50");
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
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th { background: #f8f9fa; padding: 12px; text-align: left; border-bottom: 2px solid #dee2e6; }
        td { padding: 10px; border-bottom: 1px solid #eee; }
        tr:hover { background: #f8f9fa; }
        .alert { padding: 12px; border-radius: 8px; margin-bottom: 20px; background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        @media (max-width: 768px) { .row { grid-template-columns: 1fr 1fr; } }
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
            <thead><tr><th>Data</th><th>Usuário</th><th>IP</th><th>Porta</th><th>Motivo</th><th>Ação</th></tr></thead>
            <tbody>
                <?php if ($ultimas): foreach ($ultimas as $row): ?>
                <tr>
                    <td><?php echo htmlspecialchars($row['data_consulta']); ?></td>
                    <td><?php echo htmlspecialchars($row['usuario']); ?></td>
                    <td><strong><?php echo htmlspecialchars($row['ip_consultado']); ?></strong></td>
                    <td><?php echo htmlspecialchars($row['porta_consultada']); ?></td>
                    <td><?php echo htmlspecialchars($row['motivo']); ?></td>
                    <td>
                        <a href="consultar.php?ip_publico=<?php echo urlencode($row['ip_consultado']); ?>&porta=<?php echo urlencode($row['porta_consultada']); ?>&data_inicio=<?php echo date('Y-m-d', strtotime($row['data_consulta'])); ?>&data_fim=<?php echo date('Y-m-d', strtotime($row['data_consulta'])); ?>" class="btn-sm">🔍 Reabrir</a>
                    </td>
                </tr>
                <?php endforeach; else: ?>
                <tr><td colspan="6" style="text-align:center;color:#999;">Nenhuma consulta</td></tr>
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
# 13. CONFIGURAR RSYSLOG
# ============================================================
print_header "13. CONFIGURANDO RSYSLOG"

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

mkfifo /var/run/cgnat.pipe 2>/dev/null || true
chmod 666 /var/run/cgnat.pipe 2>/dev/null || true

systemctl restart rsyslog 2>/dev/null || true
print_success "Rsyslog configurado"

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
# 15. SCRIPTS ÚTEIS (COM sync_mkauth.sh CORRIGIDO)
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

# Script de Sincronização MK-AUTH (CORRIGIDO - usa EOF sem aspas)
cat > /usr/local/bin/sync_mkauth.sh << EOF
#!/bin/bash
# Script para sincronizar dados do MK-AUTH via SSH
# Usa as tabelas sis_cliente e sis_adicional (corrigido)

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
    TRUNCATE clientes;
    
    CREATE TEMP TABLE temp_clientes (
        login text,
        nome text,
        ip_privado text
    );
    
    COPY temp_clientes (login, nome, ip_privado)
    FROM '\${TMP_FILE}'
    DELIMITER E'\t'
    CSV;
    
    INSERT INTO clientes (login, nome, ip_privado)
    SELECT 
        login,
        nome,
        ip_privado::inet
    FROM temp_clientes
    WHERE ip_privado IS NOT NULL AND ip_privado != '';
    
    SELECT 'Clientes importados: ' || COUNT(*) as status FROM clientes;
SQL
    
    rm -f "\${TMP_FILE}"
else
    echo "ERRO: Não foi possível exportar dados do MK-AUTH"
fi

echo "\$(date): Sincronização concluída."
EOF
chmod +x /usr/local/bin/sync_mkauth.sh

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

print_success "Scripts criados"

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
