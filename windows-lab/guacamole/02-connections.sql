-- RDP connections, loaded by MySQL on first start after 01-initdb.sql.
-- No credentials are stored: Guacamole prompts for the Windows user/password
-- (WIN_USER / WIN_PASSWORD from .env) when you open a connection.
-- To add a VM: copy a block, change the name and hostname.

INSERT INTO guacamole_connection (connection_name, protocol) VALUES ('app-a', 'rdp');
SET @id = LAST_INSERT_ID();
INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES
  (@id, 'hostname', 'app-a'),
  (@id, 'port', '3389'),
  (@id, 'security', 'nla'),
  (@id, 'ignore-cert', 'true'),          -- the VM's self-signed RDP cert; traffic never leaves the internal network
  (@id, 'enable-drive', 'false'),
  (@id, 'disable-upload', 'true'),
  (@id, 'disable-download', 'true'),
  (@id, 'resize-method', 'display-update');
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
  SELECT entity_id, @id, 'READ' FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER';

INSERT INTO guacamole_connection (connection_name, protocol) VALUES ('app-b', 'rdp');
SET @id = LAST_INSERT_ID();
INSERT INTO guacamole_connection_parameter (connection_id, parameter_name, parameter_value) VALUES
  (@id, 'hostname', 'app-b'),
  (@id, 'port', '3389'),
  (@id, 'security', 'nla'),
  (@id, 'ignore-cert', 'true'),
  (@id, 'enable-drive', 'false'),
  (@id, 'disable-upload', 'true'),
  (@id, 'disable-download', 'true'),
  (@id, 'resize-method', 'display-update');
INSERT INTO guacamole_connection_permission (entity_id, connection_id, permission)
  SELECT entity_id, @id, 'READ' FROM guacamole_entity WHERE name = 'guacadmin' AND type = 'USER';
