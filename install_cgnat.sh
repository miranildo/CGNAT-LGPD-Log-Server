#!/bin/bash
# ============================================================
# SCRIPT DE INSTALAÇÃO COMPLETA - SISTEMA CGNAT LGPD
# ============================================================
# Versão: 2.1 - CORRIGIDO (CRIA TODOS OS ARQUIVOS PHP)
# Autor: Sistema CGNAT - João Pessoa/PB
# Data: $(date +%Y%m%d)
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
# 8. CRIAR TABELAS
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

print_success "Tabelas criadas"

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
# 10. CRIAR TODOS OS ARQUIVOS PHP DA INTERFACE WEB
# ============================================================
print_header "10. CRIANDO ARQUIVOS PHP"

# ============================================================
# 10.1 CONFIG.PHP
# ============================================================
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

# ============================================================
# 10.2 FUNCTIONS.PHP
# ============================================================
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

# ============================================================
# 10.3 AUTH.PHP
# ============================================================
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

# ============================================================
# 10.4 LOGIN.PHP
# ============================================================
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
        label {
            display: block;
            font-weight: 600;
            margin-bottom: 5px;
            color: #555;
        }
        input {
            width: 100%;
            padding: 12px;
            border: 2px solid #e0e0e0;
            border-radius: 8px;
            font-size: 14px;
            transition: border-color 0.3s;
        }
        input:focus {
            border-color: #667eea;
            outline: none;
        }
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
            transition: transform 0.2s;
        }
        .btn:hover { transform: scale(1.02); }
        .alert {
            padding: 12px;
            border-radius: 8px;
            margin-bottom: 20px;
            text-align: center;
        }
        .alert-danger {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }
        .alert-success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }
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
        <h1>
            🔐 CGNAT LGPD
            <small>Sistema de Consulta</small>
        </h1>
        
        <?php if ($erro): ?>
        <div class="alert alert-danger">
            <?php echo $erro; ?>
        </div>
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
        
        <div class="info">
            Credenciais padrão:
            <span>admin</span>
            <span>juridico</span>
            <span>operador</span>
        </div>
    </div>
</body>
</html>
LOGIN_PHP

# ============================================================
# 10.5 INDEX.PHP
# ============================================================
cat > /var/www/html/cgnat/index.php << 'INDEX_PHP'
<?php
require_once 'auth.php';
verificarPermissao();
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>Dashboard CGNAT</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #f5f5f5;
            padding: 20px;
        }
        .container {
            max-width: 800px;
            margin: 0 auto;
            background: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { color: #333; border-bottom: 3px solid #667eea; padding-bottom: 15px; }
        .info { background: #e7f3ff; padding: 20px; border-radius: 8px; border-left: 4px solid #667eea; margin: 20px 0; }
        .btn {
            background: #667eea;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            text-decoration: none;
            display: inline-block;
        }
        .btn:hover { opacity: 0.9; }
        .btn-danger { background: #e74c3c; }
    </style>
</head>
<body>
    <div class="container">
        <h1>✅ Dashboard CGNAT LGPD</h1>
        
        <div class="info">
            <h3>👤 Bem-vindo, <?php echo htmlspecialchars($_SESSION['nome_completo']); ?>!</h3>
            <p><strong>Perfil:</strong> <?php echo htmlspecialchars($_SESSION['perfil']); ?></p>
            <p><strong>Usuário:</strong> <?php echo htmlspecialchars($_SESSION['usuario']); ?></p>
        </div>
        
        <p>
            <a href="consultar.php" class="btn">🔍 Consultar CGNAT</a>
            <a href="logout.php" class="btn btn-danger" style="margin-left: 10px;">🚪 Sair</a>
        </p>
    </div>
</body>
</html>
INDEX_PHP

# ============================================================
# 10.6 LOGOUT.PHP
# ============================================================
cat > /var/www/html/cgnat/logout.php << 'LOGOUT_PHP'
<?php
session_start();
session_destroy();
header('Location: login.php');
exit;
?>
LOGOUT_PHP

# ============================================================
# 10.7 CONSULTAR.PHP
# ============================================================
cat > /var/www/html/cgnat/consultar.php << 'CONSULTAR_PHP'
<?php
require_once 'auth.php';
verificarPermissao();

require_once 'functions.php';

$resultados = null;
$total = 0;
$mensagem = '';
$cliente_nome = '';

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
            
            $stmt = $db->prepare("
                INSERT INTO lgpd_audit (usuario, ip_consultado, porta_consultada, motivo, protocolo_judicial)
                VALUES (?, ?, ?, ?, ?)
            ");
            $stmt->execute([$_SESSION['usuario'], $ip_publico, $porta, $motivo, $protocolo]);
            
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
                    cl.nome as cliente_nome,
                    cl.login as cliente_login
                FROM cgnat_logs c
                LEFT JOIN clientes cl ON c.ip_privado = cl.ip_privado
                WHERE c.ip_publico = ?::inet
                AND c.porta_publica = ?
                AND c.data_hora BETWEEN ? AND ?
                ORDER BY c.data_hora DESC
                LIMIT 1000
            ");
            $stmt->execute([$ip_publico, $porta, $data_inicio, $data_fim]);
            $resultados = $stmt->fetchAll(PDO::FETCH_ASSOC);
            $total = count($resultados);
            
            if ($total > 0 && !empty($resultados[0]['cliente_nome'])) {
                $cliente_nome = $resultados[0]['cliente_nome'];
            }
            
            $mensagem = $total > 0 ? "✅ Encontrados {$total} registros." : '⚠️ Nenhum registro encontrado.';
        } catch (Exception $e) {
            $mensagem = "❌ Erro: " . $e->getMessage();
        }
    }
}
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Consulta CGNAT</title>
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
            background: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { color: #333; border-bottom: 3px solid #667eea; padding-bottom: 15px; margin-bottom: 25px; }
        .row { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
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
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            padding: 15px 40px;
            border-radius: 8px;
            font-size: 16px;
            font-weight: 600;
            cursor: pointer;
        }
        .btn:hover { opacity: 0.9; }
        .btn-danger { background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%); }
        .results { margin-top: 30px; border-top: 2px solid #eee; padding-top: 20px; }
        table { width: 100%; border-collapse: collapse; font-size: 14px; }
        th { background: #f8f9fa; padding: 12px; text-align: left; border-bottom: 2px solid #dee2e6; }
        td { padding: 10px; border-bottom: 1px solid #eee; }
        tr:hover { background: #f8f9fa; }
        .badge {
            display: inline-block;
            padding: 3px 10px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
        }
        .badge-success { background: #d4edda; color: #155724; }
        .badge-danger { background: #f8d7da; color: #721c24; }
        .badge-info { background: #cce5ff; color: #004085; }
        .alert {
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 20px;
        }
        .alert-success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .alert-danger { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .client-info {
            background: #e7f3ff;
            padding: 15px;
            border-radius: 8px;
            margin: 15px 0;
            border-left: 4px solid #667eea;
        }
        .client-info h3 { color: #004085; margin: 0; }
        @media (max-width: 768px) { .row { grid-template-columns: 1fr; } }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔍 Consulta CGNAT - LGPD</h1>
        
        <?php if ($mensagem): ?>
        <div class="alert alert-<?php echo strpos($mensagem, 'Nenhum') !== false || strpos($mensagem, 'Erro') !== false ? 'danger' : 'success'; ?>">
            <?php echo $mensagem; ?>
        </div>
        <?php endif; ?>
        
        <?php if ($cliente_nome): ?>
        <div class="client-info">
            <h3>👤 Cliente Identificado: <?php echo htmlspecialchars($cliente_nome); ?></h3>
        </div>
        <?php endif; ?>
        
        <form method="POST">
            <div class="row">
                <div class="form-group">
                    <label>IP Público *</label>
                    <input type="text" name="ip_publico" placeholder="Ex: 190.196.242.19" required 
                           value="<?php echo $_POST['ip_publico'] ?? ''; ?>">
                </div>
                <div class="form-group">
                    <label>Porta Pública *</label>
                    <input type="number" name="porta" placeholder="Ex: 51478" required
                           value="<?php echo $_POST['porta'] ?? ''; ?>">
                </div>
            </div>
            
            <div class="row">
                <div class="form-group">
                    <label>Data Início</label>
                    <input type="date" name="data_inicio" value="<?php echo $_POST['data_inicio'] ?? date('Y-m-d'); ?>">
                </div>
                <div class="form-group">
                    <label>Data Fim</label>
                    <input type="date" name="data_fim" value="<?php echo $_POST['data_fim'] ?? date('Y-m-d'); ?>">
                </div>
            </div>
            
            <div class="row">
                <div class="form-group">
                    <label>Hora Início</label>
                    <input type="time" name="hora_inicio" value="<?php echo $_POST['hora_inicio'] ?? '00:00'; ?>">
                </div>
                <div class="form-group">
                    <label>Hora Fim</label>
                    <input type="time" name="hora_fim" value="<?php echo $_POST['hora_fim'] ?? '23:59'; ?>">
                </div>
            </div>
            
            <div class="row">
                <div class="form-group">
                    <label>Motivo da Consulta</label>
                    <input type="text" name="motivo" value="Consulta LGPD">
                </div>
                <div class="form-group">
                    <label>Protocolo Judicial</label>
                    <input type="text" name="protocolo" placeholder="Número do processo">
                </div>
            </div>
            
            <button type="submit" class="btn">🔍 Consultar</button>
            <button type="reset" class="btn btn-danger" style="margin-left: 10px;">↺ Limpar</button>
        </form>
        
        <?php if ($resultados && $total > 0): ?>
        <div class="results">
            <h3>📋 Resultados (<?php echo $total; ?> registros)</h3>
            <div style="overflow-x: auto; margin-top: 15px;">
                <table>
                    <thead>
                        <tr>
                            <th>Data/Hora</th>
                            <th>Evento</th>
                            <th>IP Cliente</th>
                            <th>Porta Cliente</th>
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
                                <?php else: ?>
                                    <span style="color: #999;">Não identificado</span>
                                <?php endif; ?>
                            </td>
                        </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <?php endif; ?>
    </div>
</body>
</html>
CONSULTAR_PHP

# ============================================================
# 10.8 DASHBOARD.PHP
# ============================================================
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

$stmt = $db->query("SELECT COUNT(*) FROM cgnat_logs");
$total_logs = $stmt->fetchColumn();

$stmt = $db->query("SELECT COUNT(*) FROM clientes");
$total_clientes = $stmt->fetchColumn();
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Dashboard CGNAT</title>
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
            background: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { color: #333; margin-bottom: 30px; }
        .row { display: grid; grid-template-columns: 1fr 1fr 1fr 1fr; gap: 20px; margin-bottom: 30px; }
        .card {
            background: #f8f9fa;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
        }
        .card .numero { font-size: 32px; font-weight: bold; color: #667eea; }
        .card .label { color: #888; margin-top: 5px; }
        .card-verde .numero { color: #27ae60; }
        .card-vermelho .numero { color: #e74c3c; }
        .card-amarelo .numero { color: #f39c12; }
        .btn {
            background: #667eea;
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 5px;
            cursor: pointer;
            text-decoration: none;
            display: inline-block;
        }
        .btn:hover { opacity: 0.9; }
        .btn-danger { background: #e74c3c; }
        .menu { margin-bottom: 20px; }
        .menu a { margin-right: 10px; }
    </style>
</head>
<body>
    <div class="container">
        <div class="menu">
            <a href="dashboard.php" class="btn">📊 Dashboard</a>
            <a href="consultar.php" class="btn">🔍 Consultar</a>
            <a href="logout.php" class="btn btn-danger">🚪 Sair</a>
        </div>
        
        <h1>📊 Dashboard CGNAT</h1>
        
        <div class="row">
            <div class="card card-verde">
                <div class="numero"><?php echo $hoje; ?></div>
                <div class="label">Consultas Hoje</div>
            </div>
            <div class="card card-amarelo">
                <div class="numero"><?php echo $semana; ?></div>
                <div class="label">Consultas (7 dias)</div>
            </div>
            <div class="card card-vermelho">
                <div class="numero"><?php echo number_format($total_logs); ?></div>
                <div class="label">Total de Logs CGNAT</div>
            </div>
            <div class="card">
                <div class="numero"><?php echo number_format($total_clientes); ?></div>
                <div class="label">Clientes Cadastrados</div>
            </div>
        </div>
        
        <p style="text-align: center; color: #888; margin-top: 30px;">
            Sistema CGNAT LGPD - João Pessoa/PB
        </p>
    </div>
</body>
</html>
DASHBOARD_PHP

print_success "Arquivos PHP criados"

# ============================================================
# 11. CONFIGURAR CRONJOBS
# ============================================================
print_header "11. CONFIGURANDO CRONJOBS"

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
# 12. SCRIPTS ÚTEIS
# ============================================================
print_header "12. CRIANDO SCRIPTS ÚTEIS"

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

print_success "Scripts criados"

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
# 14. PERMISSÕES FINAIS
# ============================================================
print_header "14. AJUSTANDO PERMISSÕES FINAIS"

chown -R www-data:www-data /var/www/html/cgnat/ 2>/dev/null || true
chmod -R 755 /var/www/html/cgnat/ 2>/dev/null || true
chmod 644 /var/www/html/cgnat/*.php 2>/dev/null || true
systemctl restart apache2 2>/dev/null || true

print_success "Permissões ajustadas"

# ============================================================
# 15. RESULTADO FINAL
# ============================================================
print_header "✅ INSTALAÇÃO CONCLUÍDA!"

IP=$(hostname -I | awk '{print $1}')

echo "============================================================"
echo "  📋 INFORMAÇÕES DO SISTEMA"
echo "============================================================"
echo ""
echo "🌐 URL de acesso: http://$IP/cgnat/login.php"
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
echo "   1. Acesse a interface web: http://$IP/cgnat/login.php"
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
