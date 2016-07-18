# Installing graphite to Centos 6.5

if [ -z $GRAPHITE_RELEASE ]; then
    GRAPHITE_RELEASE='0.9.15'
fi

/etc/init.d/iptables stop
chkconfig iptables off

# Firs you need to install python 2.7 since in repos there's only 2.6 and latest graphite doesn't work with it.


# Install development tools:
yum groupinstall -y 'development tools'

#Also you need the packages below to enable SSL, bz2, zlib for Python and some utils:
yum install -y zlib-devel bzip2-devel openssl-devel ncurses-devel sqlite-devel readline-devel tk-devel gdbm-devel db4-devel libpcap-devel xz-devel glibc-devel xz-libs wget libffi-devel openssl openssl-devel cyrus-sasl-devel openldap-devel rrdtool-devel httpd httpd-devel


# Installing Python 2.7.12 from source
mkdir /opt/src
cd /opt/src
wget https://www.python.org/ftp/python/2.7.12/Python-2.7.12.tar.xz
tar -xvf Python-2.7.12.tar.xz
cd Python-2.7.12/
./configure --prefix=/opt/usr/local --enable-shared
make
make altinstall

echo "/opt/usr/local/lib" > /etc/ld.so.conf.d/python27.conf
ldconfig

echo 'pathmunge /opt/usr/local/bin' > /etc/profile.d/python27.sh
chmod +x /etc/profile.d/python27.sh
. /etc/profile


# # Install pip
python2.7 -m ensurepip
pip2.7 install -U pip

# Install virtulaenv
pip2.7 install virtualenv 

# virtualenv /opt/graphite
virtualenv --python=/opt/usr/local/bin/python2.7 /opt/graphite

source /opt/graphite/bin/activate

pip2.7 install rrdtool python-ldap

cd /opt/src/
git clone https://github.com/graphite-project/whisper.git
git clone https://github.com/graphite-project/carbon.git
git clone https://github.com/graphite-project/graphite-web.git

# Build and install Whisper Carbon and Graphite
cd whisper; git checkout ${GRAPHITE_RELEASE}; python setup.py install
cd ../carbon; git checkout ${GRAPHITE_RELEASE}; pip install -r requirements.txt; python setup.py install

cd ../graphite-web; git checkout ${GRAPHITE_RELEASE}; pip install -r requirements.txt; python check-dependencies.py; python setup.py install

cd /opt/graphite/webapp/graphite
python manage.py syncdb --noinput


# Configs

cat << EOF > /opt/graphite/conf/carbon.conf
[cache]
USER = carbon
MAX_CACHE_SIZE = inf
MAX_CREATES_PER_MINUTE = 100
MAX_UPDATES_PER_SECOND = 1000
LINE_RECEIVER_INTERFACE = 0.0.0.0
PICKLE_RECEIVER_INTERFACE = 0.0.0.0
CACHE_QUERY_INTERFACE = 0.0.0.0
LOG_CACHE_HITS = False
LOG_CACHE_QUEUE_SORTS = False
LOG_UPDATES = False

[cache:1]
LINE_RECEIVER_PORT = 2003
PICKLE_RECEIVER_PORT = 2004
CACHE_QUERY_PORT = 7002

EOF


cat << EOF > /opt/graphite/conf/storage-schemas.conf
[collectd]
pattern = ^collectd\.
retentions = 10s:1w, 60s:1y

[default]
pattern = .*
retentions = 60s:1y

EOF


# System preparations
groupadd carbon
useradd -c "Carbon user" -g carbon -s /bin/false carbon

chmod 775 /opt/graphite/storage
chown apache:carbon /opt/graphite/storage
chown -R carbon /opt/graphite/storage/whisper
mkdir -p /opt/graphite/storage/log/carbon-{cache,relay,aggregator}
chown -R carbon:carbon /opt/graphite/storage/log

carbon-cache.py --instance=1 start

# for i in `seq 8`; do sudo -E carbon-cache.py --instance=${i} start; done
# for i in `seq 8`; do sudo -E carbon-cache.py --instance=${i} stop; done

cd /opt/graphite/webapp/graphite
cp local_settings.py.example local_settings.py

sed -i -e "s/UNSAFE_DEFAULT/`date | md5sum | cut -d ' ' -f 1`/" local_settings.py
sed -i -e "s/#SECRET_KEY/SECRET_KEY/" local_settings.py

chown apache /opt/graphite/storage/log/webapp

# Setting up Apache
cd /opt/graphite/conf
cp graphite.wsgi.example graphite.wsgi

cat << EOF > /etc/httpd/conf.d/graphite.conf
# WSGISocketPrefix /var/log/httpd
# WSGIPythonHome /opt/graphite
# WSGIPythonPath /opt/graphite:/opt/graphite/lib/python2.7/site-packages

WSGIDaemonProcess graphiteweb python-path=/opt/graphite:/opt/graphite/lib/python2.7/site-packages
WSGIProcessGroup graphiteweb
WSGIApplicationGroup %{GLOBAL}
WSGIImportScript /opt/graphite/conf/graphite.wsgi process-group=graphiteweb application-group=%{GLOBAL}
WSGIScriptAlias / /opt/graphite/conf/graphite.wsgi

<VirtualHost *:80>
  # wsgi script and permissions to read it
  #WSGIDaemonProcess sampleapp python-path=/opt/graphite/webapp:/opt/graphite/lib/python2.7/site-packages
  #WSGIProcessGroup sampleapp
  # WSGISocketPrefix /opt/graphite/storage
  WSGIScriptAlias / /opt/graphite/conf/graphite.wsgi
  <Directory /opt/graphite/conf>
    # Require all granted
  </Directory>
</VirtualHost>

EOF

cd /opt/src
git clone https://github.com/GrahamDumpleton/mod_wsgi
cd mod_wsgi
git checkout 4.5.3
./configure
make
make install

mkdir -p /opt/usr/lib64/httpd/modules/
mv /usr/lib64/httpd/modules/mod_wsgi.so /opt/usr/lib64/httpd/modules/
echo "LoadModule wsgi_module /opt/usr/lib64/httpd/modules/mod_wsgi.so" > /etc/httpd/conf.d/wsgi.conf 

/etc/init.d/httpd restart
