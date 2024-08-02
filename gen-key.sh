#!/bin/bash

function gen_passphrase() {
  local _default_passphrase_length=20
  local _words_number=0
  local _passphrase=""

  if ! local _absolute_path="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"; then
   echo "[NOK] An error has occured while trying to determine absolute path."
   return 1
  fi

  _diceware_list_file="${_absolute_path}/diceware-list.csv"

  if [ ! -f "${_diceware_list_file}" ]; then
   echo "[NOK] Diceware list file not found with path ${_diceware_list_file}."
   return 1
  fi

  if [ ! -z "$1" ] && \
  echo "$1" | grep -Eq "^[0-9]{1,2}$" && \
  [ "$1" -gt 0 ]; then
    _passphrase_length="$1"
  else
    _passphrase_length="$_default_passphrase_length"
  fi

  while [ ${#_passphrase} -lt $_passphrase_length ] || [ $_words_number -lt 5 ] ; do
    unset _random_word_number

    for i in {1..5}; do
       _random_word_number+="$((( RANDOM % 6 ) + 1 ))"
    done

    if grep -Eq "^${_random_word_number}\s" "${_diceware_list_file}" && \
    _random_word="$(grep -E "^${_random_word_number}\s" "${_diceware_list_file}" | cut -d' ' -f 2 | tr -d '\r')"; then
      if [ -z "$_passphrase" ]; then
      _passphrase="$_random_word"
      else
        _passphrase+="-${_random_word}"
      fi

      _words_number=$((_words_number + 1))
    else
      echo "[NOK] Unable to find a word in diceware list file with number ${_random_word_number}."
      return 1
    fi
  done

  echo "$_passphrase"
  return 0
}

function gen_key() {
  if ! command -v openssl &> /dev/null; then
    echo "[NOK] Please install openssl prior to execute this script."
    return 1
  fi

  if ! command -v ssh-keygen &> /dev/null; then
    echo "[NOK] Please install openssh(-client) prior to execute this script."
    return 1
  fi

  read -p 'Please define an alias (default: "default"): ' _key_alias
  echo -e '\b'

  if [ -z $_key_alias ]; then
    _key_alias='default'
  fi

  _key_alias="${_key_alias}-key"

  if ! mkdir -p "$_key_alias"; then
    echo "[NOK] An error has occurred while trying to create \"$_key_alias\" folder."
  fi

  cd "$_key_alias"

  read -p "Would you like to automate passphrase creation? (recommended) [Y/n]: " _passphrase_creation_bool

  if [ "$_passphrase_creation_bool" != "n" ]; then
    echo -e "\nGenerating passphrase..."

    _passphrase="$(gen_passphrase)"

    echo -e '✓ Passphrase has been generated, it will be disclosed later.'
  else
    while [ ${#_passphrase} -lt 10 ]; do
      read -s -p 'Enter a passphrase (10 char. min.): ' _passphrase
      echo -e '\b'

      if [ -z $_passphrase ]; then
        echo -e "\nPassphrase has not been set, therefore generating it..."

        _passphrase="$(gen_passphrase)"
        _confirm_passphrase=$_passphrase

        echo -e 'ℹ A default passphrase has been set, it will be disclosed later.'
      fi
    done

    while [ "$_passphrase" != "$_confirm_passphrase" ]; do
      read -s -p 'Confirm passphrase: ' _confirm_passphrase
    done
  fi

  echo -e '\b'

  read -p 'Enter common name (default: www.domain.com): ' _common_name

  if [ -z $_common_name ]; then
    _common_name='www.domain.com'
  fi

  if ! rm -rf ${_key_alias}.prv ${_key_alias}.crt ${_key_alias}.ssh.prv ${_key_alias}.pub ${_key_alias}.ssh.pub ${_key_alias}.p12; then
    echo "[NOK] An error has occured while trying to delete previous files."
  fi

  if echo -e "\nGenerating private key (including self-signed certificate)..." && \
  openssl req -x509 -newkey rsa:4096 -passout pass:${_passphrase} -sha256 -days 3650 -keyout ${_key_alias}.prv -out ${_key_alias}.crt -subj "/CN=${_common_name}" &> /dev/null; then
    echo "✓ \033[1m${_key_alias}.prv\033[0m, \033[1m${_key_alias}.crt\033[0m (CN: \033[1m${_common_name}\033[0m) have been successfully written."
  else
    echo "[NOK] An error has occurred while trying to generate private key (including self-signed certificate), ${_key_alias}.prv & ${_key_alias}.crt files."
    return 1
  fi

  if echo -e "\nGenerating SSH private key..." && \
  cp ${_key_alias}.prv ${_key_alias}.ssh.prv && \
  ssh-keygen -i -m PEM -p -P ${_passphrase} -N ${_passphrase} -f ${_key_alias}.ssh.prv &> /dev/null; then
    echo "✓ \033[1m${_key_alias}.ssh.prv\033[0m has been successfully written."
  else
    echo "[NOK] An error has occurred while trying to generate SSH private key, ${_key_alias}.ss.prv file."
    return 1
  fi

  if echo -e "\nGenerating public key..." && \
  openssl pkey -in ${_key_alias}.prv -passin pass:${_passphrase} -pubout -out ${_key_alias}.pub; then
    echo "✓ \033[1m${_key_alias}.pub\033[0m has been successfully written."
  else
    echo "[NOK] An error has occurred while trying to generate public key, ${_key_alias}.pub file."
    return 1
  fi

  if echo -e "\nGenerating SSH public key..." && \
  ssh-keygen -i -m PKCS8 -f ${_key_alias}.pub > ${_key_alias}.ssh.pub; then
    echo "✓ \033[1m${_key_alias}.ssh.pub\033[0m has been successfully written."
  else
    echo "[NOK] An error has occurred while trying to generate SSH public key, ${_key_alias}.ssh.pub file."
    return 1
  fi

  if echo -e "\nGenerating p12 key..." && \
  openssl pkcs12 -inkey ${_key_alias}.prv -passin pass:${_passphrase} -in ${_key_alias}.crt -passout pass:${_passphrase} -export -out ${_key_alias}.p12; then
    echo -e "✓ \033[1m${_key_alias}.p12\033[0m has been successfully written."
  else
    echo "[NOK] An error has occurred while trying to generate p12 key, ${_key_alias}.p12 file."
    return 1
  fi

  echo -e "\n\033[32m✓ All the files have been saved into folder \"\033[1m${_key_alias}\033[0m\033[32m\".\033[0m"

  echo -e "\nThe key's passphrase is: \033[1m${_passphrase}\033[0m |  \033[36mStore it in a safe place!\033[0m"

  cd ..

  echo -e '\nThe console is about to be cleared in \033[1m60 seconds\033[0m.'

  sleep 60 && clear

  return 0
}

gen_key