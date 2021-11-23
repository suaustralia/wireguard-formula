# -*- coding: utf-8 -*-
# vim: ft=sls

{#- Get the `tplroot` from `tpldir` #}
{%- set tplroot = tpldir.split('/')[0] %}
{%- set sls_package_install = tplroot ~ '.package.install' %}
{%- from tplroot ~ "/map.jinja" import wireguard with context %}
{%- from tplroot ~ "/libtofs.jinja" import files_switch with context %}

include:
  - {{ sls_package_install }}

{%- set interfaces = wireguard.get('interfaces', {}) %}

{%- if interfaces|length() > 0 %}
wireguard-config-file-mine-update:
  module.run:
    - name: mine.update
{%- endif %}

{%- for interface, config in interfaces.items() %}

{%-   set private_key = "{}/{}.priv".format(wireguard.config, interface) %}
{%-   set public_key = "{}/{}.pub".format(wireguard.config, interface) %}
{%-   set private_key_specified = config.get('Interface', {}).get('PrivateKey', False) %}

{%-   if not private_key_specified %}
wireguard-config-file-interface-{{ interface }}-private-key:
  cmd.run:
    - umask: "027"
    - name: wg genkey > {{ private_key }}
    - creates: {{ private_key }}
    - require_in:
      - file: "wireguard-config-file-interface-{{ interface }}-config-netdev"

wireguard-config-file-interface-{{ interface }}-public-key:
  cmd.run:
    # Show public key for easier debugging
    - name: wg pubkey < {{ private_key }} | tee {{ public_key }}
    - creates: {{ public_key }}
    - onchanges:
      - cmd: wireguard-config-file-interface-{{ interface }}-private-key
    - onchanges_in:
      - module: wireguard-config-file-mine-update

{%-     set wg_set_private_key = "wg set %i private-key {}".format(private_key) %}
{%-     set pillar_post_up = config.get('PostUp', 'true') %}
{%-     do config['Interface'].update({"PostUp": "{} && ({})".format(wg_set_private_key, pillar_post_up)}) %}
{%-   endif %}

"wireguard-config-file-interface-{{ interface }}-config-netdev":
  file.managed:
    - name: {{ wireguard.config }}/{{ interface }}.netdev
    - source: {{ files_switch(['netdev.jinja'],
                              lookup='wireguard-config-file-interface-{}-config'.format(interface)
                 )
              }}
    - mode: 660
    - user: root
    - group: {{ wireguard.rootgroup }}
    - makedirs: True
    - template: jinja
    - require:
      - sls: {{ sls_package_install }}
    - context:
        interface: {{ interface }}
        interface_config: {{ config | json }}
        private_key_file: {{ private_key }}

"wireguard-config-file-interface-{{ interface }}-config-network":
  file.managed:
    - name: {{ wireguard.config }}/{{ interface }}.network
    - source: {{ files_switch(['network.jinja'],
                              lookup='wireguard-config-file-interface-{}-config'.format(interface)
                 )
              }}
    - mode: 660
    - user: root
    - group: {{ wireguard.rootgroup }}
    - makedirs: True
    - template: jinja
    - require:
      - sls: {{ sls_package_install }}
    - context:
        interface: {{ interface }}
        interface_config: {{ config | json }}
{%- endfor %}
