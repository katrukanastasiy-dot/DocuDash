import streamlit as st
import pandas as pd
import json
import os
from datetime import datetime, timedelta
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from pathlib import Path
import uuid
import shutil

# Константы
DATA_FILE = "data/instructions.json"
UPLOADS_DIR = "uploads"

def load_data():
    """Загрузка данных из JSON файла"""
    if os.path.exists(DATA_FILE):
        try:
            with open(DATA_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except:
            return []
    return []

def save_data(data):
    """Сохранение данных в JSON файл"""
    with open(DATA_FILE, 'w', encoding='utf-8') as f:
        json.dump(data, f, ensure_ascii=False, indent=2)

def add_history_entry(instruction, change_type, details, user="Система"):
    """Добавление записи в историю изменений"""
    if 'history' not in instruction:
        instruction['history'] = []
    
    history_entry = {
        'timestamp': datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        'change_type': change_type,
        'details': details,
        'user': user
    }
    
    instruction['history'].append(history_entry)
    return instruction

def send_email(to_email, subject, body, yandex_email, yandex_password):
    """Отправка email через Яндекс.Почту"""
    try:
        msg = MIMEMultipart()
        msg['From'] = yandex_email
        msg['To'] = to_email
        msg['Subject'] = subject
        
        msg.attach(MIMEText(body, 'plain', 'utf-8'))
        
        server = smtplib.SMTP('smtp.yandex.ru', 587)
        server.starttls()
        server.login(yandex_email, yandex_password)
        text = msg.as_string()
        server.sendmail(yandex_email, to_email, text)
        server.quit()
        return True
    except Exception as e:
        st.error(f"Ошибка отправки email: {str(e)}")
        return False

def is_outdated(last_update_date, months_threshold=12):
    """Проверка, требует ли инструкция актуализации"""
    if not last_update_date:
        return True
    
    try:
        update_date = datetime.strptime(last_update_date, "%Y-%m-%d")
        threshold_date = datetime.now() - timedelta(days=months_threshold * 30)
        return update_date < threshold_date
    except:
        return True

def main():
    # Создание необходимых директорий — ГАРАНТИРОВАННО ПЕРЕД ИСПОЛЬЗОВАНИЕМ
    os.makedirs("data", exist_ok=True)
    os.makedirs(UPLOADS_DIR, exist_ok=True)
    
    st.title("📋 Дашборд управления должностными инструкциями")
    
    # Загрузка данных
    data = load_data()
    
    # Боковая панель с навигацией
    st.sidebar.title("Навигация")
    page = st.sidebar.radio("Выберите раздел:", [
        "📊 Обзор инструкций",
        "➕ Добавить инструкцию", 
        "✏️ Редактировать инструкцию",
        "📧 Отправить напоминания",
        "📈 Статистика и аналитика",
        "⚙️ Автоматические напоминания"
    ])
    
    if page == "📊 Обзор инструкций":
        show_instructions_overview(data)
    elif page == "➕ Добавить инструкцию":
        add_instruction(data)
    elif page == "✏️ Редактировать инструкцию":
        edit_instruction(data)
    elif page == "📧 Отправить напоминания":
        send_reminders(data)
    elif page == "📈 Статистика и аналитика":
        show_statistics(data)
    elif page == "⚙️ Автоматические напоминания":
        auto_reminders(data)

def show_instructions_overview(data):
    """Отображение обзора всех инструкций"""
    st.header("📊 Обзор должностных инструкций")
    
    if not data:
        st.info("📝 Нет добавленных инструкций. Используйте раздел 'Добавить инструкцию' для создания первой записи.")
        return
    
    # Фильтры
    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        search_term = st.text_input("🔍 Поиск по названию:")
    
    with col2:
        department_filter = st.selectbox(
            "🏢 Фильтр по подразделению:",
            ["Все"] + list(set([item.get('department', '') for item in data if item.get('department')]))
        )
    
    with col3:
        responsible_filter = st.selectbox(
            "👤 Фильтр по ответственному:",
            ["Все"] + list(set([item.get('responsible', '') for item in data if item.get('responsible')]))
        )
    
    with col4:
        status_filter = st.selectbox(
            "⚠️ Статус актуализации:",
            ["Все", "Требует актуализации", "Актуальные"]
        )
    
    # Фильтрация данных
    filtered_data = data.copy()
    
    if search_term:
        filtered_data = [item for item in filtered_data 
                        if search_term.lower() in item.get('title', '').lower()]
    
    if department_filter != "Все":
        filtered_data = [item for item in filtered_data 
                        if item.get('department') == department_filter]
    
    if responsible_filter != "Все":
        filtered_data = [item for item in filtered_data 
                        if item.get('responsible') == responsible_filter]
    
    if status_filter != "Все":
        if status_filter == "Требует актуализации":
            filtered_data = [item for item in filtered_data 
                            if is_outdated(item.get('last_update'))]
        else:
            filtered_data = [item for item in filtered_data 
                            if not is_outdated(item.get('last_update'))]
    
    # Статистика
    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        st.metric("Всего инструкций", len(data))
    
    with col2:
        outdated_count = sum(1 for item in data if is_outdated(item.get('last_update')))
        st.metric("Требуют актуализации", outdated_count)
    
    with col3:
        with_files = sum(1 for item in data if item.get('has_file'))
        st.metric("С файлами", with_files)
    
    with col4:
        without_files = len(data) - with_files
        st.metric("Без файлов", without_files)
    
    # Таблица инструкций
    if filtered_data:
        st.subheader(f"📋 Найдено записей: {len(filtered_data)}")
        
        # Подготовка данных для таблицы
        table_data = []
        for item in filtered_data:
            status = "🔴 Требует актуализации" if is_outdated(item.get('last_update')) else "🟢 Актуальная"
            file_status = "✅ Есть" if item.get('has_file') else "❌ Нет"
            
            table_data.append({
                "Название": item.get('title', ''),
                "Подразделение": item.get('department', 'Не указано'),
                "Дата регистрации": item.get('registration_date', ''),
                "Дата актуализации": item.get('last_update', 'Не указана'),
                "Ответственный": item.get('responsible', ''),
                "Email": item.get('email', ''),
                "Файл": file_status,
                "Статус": status
            })
        
        df = pd.DataFrame(table_data)
        st.dataframe(df, use_container_width=True)
        
        # Загрузка файлов
        st.subheader("📎 Файлы инструкций")
        for item in filtered_data:
            if item.get('has_file') and item.get('filename'):
                file_path = os.path.join(UPLOADS_DIR, item['filename'])
                if os.path.exists(file_path):
                    with open(file_path, 'rb') as f:
                        st.download_button(
                            label=f"📄 Скачать: {item['title']}",
                            data=f.read(),
                            file_name=item['filename'],
                            key=f"download_{item['id']}"
                        )
    else:
        st.info("🔍 По заданным фильтрам ничего не найдено.")

def add_instruction(data):
    """Добавление новой инструкции"""
    st.header("➕ Добавление новой должностной инструкции")
    
    with st.form("add_instruction_form"):
        title = st.text_input("📋 Название должностной инструкции*:")
        department = st.text_input("🏢 Подразделение*:")
        
        col1, col2 = st.columns(2)
        with col1:
            registration_date = st.date_input("📅 Дата регистрации*:", datetime.now())
        with col2:
            last_update = st.date_input("🔄 Дата последней актуализации*:", datetime.now())
        
        responsible = st.text_input("👤 Ответственное лицо*:")
        email = st.text_input("📧 Email ответственного*:")
        
        uploaded_file = st.file_uploader(
            "📎 Загрузить файл инструкции:",
            type=['pdf', 'doc', 'docx', 'txt']
        )
        
        submitted = st.form_submit_button("✅ Добавить инструкцию")
        
        if submitted:
            if not all([title, department, registration_date, last_update, responsible, email]):
                st.error("❌ Заполните все обязательные поля (отмечены *)")
                return
            
            # Создание новой записи
            new_instruction = {
                'id': str(uuid.uuid4()),
                'title': title,
                'department': department,
                'registration_date': registration_date.strftime("%Y-%m-%d"),
                'last_update': last_update.strftime("%Y-%m-%d"),
                'responsible': responsible,
                'email': email,
                'has_file': uploaded_file is not None,
                'filename': None,
                'history': [],
                'file_versions': []
            }
            
            # Добавление записи в историю
            add_history_entry(new_instruction, 'Создание', f'Создана новая инструкция "{title}"')
            
            # Сохранение файла
            if uploaded_file:
                filename = f"{new_instruction['id']}_{uploaded_file.name}"
                file_path = os.path.join(UPLOADS_DIR, filename)
                with open(file_path, 'wb') as f:
                    f.write(uploaded_file.read())
                new_instruction['filename'] = filename
                add_history_entry(new_instruction, 'Файл', f'Загружен файл: {uploaded_file.name}')
            
            # Добавление в данные
            data.append(new_instruction)
            save_data(data)
            
            st.success("✅ Инструкция успешно добавлена!")
            st.rerun()

def edit_instruction(data):
    """Редактирование существующей инструкции"""
    st.header("✏️ Редактирование должностной инструкции")
    
    if not data:
        st.info("📝 Нет инструкций для редактирования. Добавьте сначала инструкцию.")
        return
    
    # Выбор инструкции для редактирования
    instruction_options = {item['title']: item['id'] for item in data}
    selected_title = st.selectbox("📋 Выберите инструкцию для редактирования:", 
                                 list(instruction_options.keys()))
    
    if selected_title:
        selected_id = instruction_options[selected_title]
        instruction = next(item for item in data if item['id'] == selected_id)
        
        # Отображение истории изменений
        if instruction.get('history'):
            with st.expander("📜 История изменений", expanded=False):
                for entry in reversed(instruction['history']):
                    st.markdown(f"**{entry['timestamp']}** - _{entry['change_type']}_")
                    st.text(entry['details'])
                    st.divider()
        
        # Отображение версий файлов
        if instruction.get('file_versions'):
            with st.expander("📁 Предыдущие версии файлов", expanded=False):
                for version in reversed(instruction['file_versions']):
                    col1, col2 = st.columns([3, 1])
                    with col1:
                        st.text(f"v{version['version']} - {version['original_name']} ({version['timestamp']})")
                    with col2:
                        file_path = os.path.join(UPLOADS_DIR, version['filename'])
                        if os.path.exists(file_path):
                            with open(file_path, 'rb') as f:
                                st.download_button(
                                    label="📥",
                                    data=f.read(),
                                    file_name=version['original_name'],
                                    key=f"version_{version['version']}_{selected_id}"
                                )
        
        with st.form("edit_instruction_form"):
            title = st.text_input("📋 Название:", value=instruction.get('title', ''))
            department = st.text_input("🏢 Подразделение:", value=instruction.get('department', ''))
            
            col1, col2 = st.columns(2)
            with col1:
                reg_date = datetime.strptime(instruction.get('registration_date', '2024-01-01'), "%Y-%m-%d")
                registration_date = st.date_input("📅 Дата регистрации:", value=reg_date)
            with col2:
                update_date = datetime.strptime(instruction.get('last_update', '2024-01-01'), "%Y-%m-%d")
                last_update = st.date_input("🔄 Дата актуализации:", value=update_date)
            
            responsible = st.text_input("👤 Ответственное лицо:", 
                                      value=instruction.get('responsible', ''))
            email = st.text_input("📧 Email:", value=instruction.get('email', ''))
            
            # Информация о текущем файле
            if instruction.get('has_file'):
                st.info(f"📎 Текущий файл: {instruction.get('filename', 'Неизвестно')}")
            
            uploaded_file = st.file_uploader(
                "📎 Загрузить новый файл (необязательно):",
                type=['pdf', 'doc', 'docx', 'txt']
            )
            
            col1, col2 = st.columns(2)
            with col1:
                update_submitted = st.form_submit_button("✅ Обновить")
            with col2:
                delete_submitted = st.form_submit_button("🗑️ Удалить", type="secondary")
            
            if update_submitted:
                if not all([title, department, registration_date, last_update, responsible, email]):
                    st.error("❌ Заполните все поля")
                    return
                
                # Инициализация полей для совместимости со старыми данными
                if 'history' not in instruction:
                    instruction['history'] = []
                if 'file_versions' not in instruction:
                    instruction['file_versions'] = []
                
                # Отслеживание изменений
                changes = []
                if instruction.get('title') != title:
                    changes.append(f"Название: '{instruction.get('title')}' → '{title}'")
                if instruction.get('department') != department:
                    changes.append(f"Подразделение: '{instruction.get('department', 'не указано')}' → '{department}'")
                if instruction.get('registration_date') != registration_date.strftime("%Y-%m-%d"):
                    changes.append(f"Дата регистрации изменена")
                if instruction.get('last_update') != last_update.strftime("%Y-%m-%d"):
                    changes.append(f"Дата актуализации обновлена")
                if instruction.get('responsible') != responsible:
                    changes.append(f"Ответственный: '{instruction.get('responsible')}' → '{responsible}'")
                if instruction.get('email') != email:
                    changes.append(f"Email изменен")
                
                # Обновление данных
                instruction.update({
                    'title': title,
                    'department': department,
                    'registration_date': registration_date.strftime("%Y-%m-%d"),
                    'last_update': last_update.strftime("%Y-%m-%d"),
                    'responsible': responsible,
                    'email': email
                })
                
                if changes:
                    add_history_entry(instruction, 'Редактирование', '; '.join(changes))
                
                # Обработка нового файла с версионированием
                if uploaded_file:
                    # Сохранение старой версии файла
                    if instruction.get('filename'):
                        old_filename = instruction['filename']
                        old_file_path = os.path.join(UPLOADS_DIR, old_filename)
                        if os.path.exists(old_file_path):
                            # Создание версионированной копии
                            version_num = len(instruction.get('file_versions', [])) + 1
                            version_filename = f"{instruction['id']}_v{version_num}_{old_filename.split('_', 1)[-1]}"
                            version_path = os.path.join(UPLOADS_DIR, version_filename)
                            
                            # Копирование старого файла в версию
                            shutil.copy2(old_file_path, version_path)
                            
                            # Добавление в историю версий
                            instruction['file_versions'].append({
                                'version': version_num,
                                'filename': version_filename,
                                'original_name': old_filename.split('_', 1)[-1],
                                'timestamp': datetime.now().strftime("%Y-%m-%d %H:%M:%S")
                            })
                            
                            # Удаление старого файла
                            os.remove(old_file_path)
                    
                    # Сохранение нового файла
                    filename = f"{instruction['id']}_{uploaded_file.name}"
                    file_path = os.path.join(UPLOADS_DIR, filename)
                    with open(file_path, 'wb') as f:
                        f.write(uploaded_file.read())
                    
                    instruction['filename'] = filename
                    instruction['has_file'] = True
                    
                    add_history_entry(instruction, 'Файл', f'Загружена новая версия файла: {uploaded_file.name}')
                
                save_data(data)
                st.success("✅ Инструкция успешно обновлена!")
                st.rerun()
            
            if delete_submitted:
                # Подтверждение удаления
                if st.session_state.get(f'confirm_delete_{selected_id}'):
                    # Удаление файла
                    if instruction.get('filename'):
                        file_path = os.path.join(UPLOADS_DIR, instruction['filename'])
                        if os.path.exists(file_path):
                            os.remove(file_path)
                    
                    # Удаление из данных
                    data.remove(instruction)
                    save_data(data)
                    
                    del st.session_state[f'confirm_delete_{selected_id}']
                    st.success("✅ Инструкция успешно удалена!")
                    st.rerun()
                else:
                    st.session_state[f'confirm_delete_{selected_id}'] = True
                    st.warning("⚠️ Нажмите 'Удалить' еще раз для подтверждения")
                    st.rerun()

def send_reminders(data):
    """Отправка напоминаний по email"""
    st.header("📧 Отправка напоминаний")
    
    if not data:
        st.info("📝 Нет инструкций для отправки напоминаний.")
        return
    
    # Настройки email
    st.subheader("⚙️ Настройки отправки")
    
    col1, col2 = st.columns(2)
    with col1:
        yandex_email = st.text_input("📧 Ваш email на Яндексе:")
    with col2:
        yandex_password = st.text_input("🔐 Пароль приложения:", type="password")
    
    st.info("ℹ️ Используйте пароль приложения Яндекс.Почты, не основной пароль от аккаунта")
    
    # Анализ инструкций, требующих актуализации
    outdated_instructions = [item for item in data if is_outdated(item.get('last_update'))]
    instructions_without_files = [item for item in data if not item.get('has_file')]
    
    if outdated_instructions:
        st.subheader("⚠️ Инструкции, требующие актуализации")
        for item in outdated_instructions:
            with st.expander(f"📋 {item['title']} - {item.get('responsible', 'Не указан')}"):
                st.write(f"**Дата последней актуализации:** {item.get('last_update', 'Не указана')}")
                st.write(f"**Ответственный:** {item.get('responsible', '')}")
                st.write(f"**Email:** {item.get('email', '')}")
                
                if st.button(f"📧 Отправить напоминание об актуализации", 
                           key=f"send_update_{item['id']}"):
                    if yandex_email and yandex_password:
                        subject = f"Напоминание об актуализации должностной инструкции: {item['title']}"
                        body = f"""Уважаемый {item.get('responsible', 'коллега')}!

Напоминаем, что должностная инструкция "{item['title']}" требует актуализации.

Дата последней актуализации: {item.get('last_update', 'не указана')}
Дата регистрации: {item.get('registration_date', 'не указана')}

Просьба обновить инструкцию в ближайшее время.

С уважением,
Система управления должностными инструкциями"""
                        
                        if send_email(item.get('email'), subject, body, yandex_email, yandex_password):
                            st.success(f"✅ Напоминание отправлено {item.get('responsible')}")
                        else:
                            st.error(f"❌ Ошибка отправки {item.get('responsible')}")
                    else:
                        st.error("❌ Заполните email и пароль")
    
    if instructions_without_files:
        st.subheader("📄 Инструкции без файлов")
        for item in instructions_without_files:
            with st.expander(f"📋 {item['title']} - {item.get('responsible', 'Не указан')}"):
                st.write(f"**Ответственный:** {item.get('responsible', '')}")
                st.write(f"**Email:** {item.get('email', '')}")
                
                if st.button(f"📧 Отправить напоминание о загрузке файла", 
                           key=f"send_file_{item['id']}"):
                    if yandex_email and yandex_password:
                        subject = f"Необходимо загрузить файл должностной инструкции: {item['title']}"
                        body = f"""Уважаемый {item.get('responsible', 'коллега')}!

Для должностной инструкции "{item['title']}" не загружен файл.

Дата регистрации: {item.get('registration_date', 'не указана')}

Просьба загрузить файл инструкции в систему.

С уважением,
Система управления должностными инструкциями"""
                        
                        if send_email(item.get('email'), subject, body, yandex_email, yandex_password):
                            st.success(f"✅ Напоминание отправлено {item.get('responsible')}")
                        else:
                            st.error(f"❌ Ошибка отправки {item.get('responsible')}")
                    else:
                        st.error("❌ Заполните email и пароль")
    
    # Массовая отправка
    if outdated_instructions or instructions_without_files:
        st.subheader("📨 Массовая отправка")
        
        col1, col2 = st.columns(2)
        with col1:
            if outdated_instructions and st.button("📧 Отправить всем напоминания об актуализации"):
                if yandex_email and yandex_password:
                    success_count = 0
                    for item in outdated_instructions:
                        subject = f"Напоминание об актуализации должностной инструкции: {item['title']}"
                        body = f"""Уважаемый {item.get('responsible', 'коллега')}!

Напоминаем, что должностная инструкция "{item['title']}" требует актуализации.

Дата последней актуализации: {item.get('last_update', 'не указана')}
Дата регистрации: {item.get('registration_date', 'не указана')}

Просьба обновить инструкцию в ближайшее время.

С уважением,
Система управления должностными инструкциями"""
                        
                        if send_email(item.get('email'), subject, body, yandex_email, yandex_password):
                            success_count += 1
                    
                    st.success(f"✅ Отправлено {success_count} из {len(outdated_instructions)} напоминаний")
                else:
                    st.error("❌ Заполните email и пароль")
        
        with col2:
            if instructions_without_files and st.button("📧 Отправить всем напоминания о файлах"):
                if yandex_email and yandex_password:
                    success_count = 0
                    for item in instructions_without_files:
                        subject = f"Необходимо загрузить файл должностной инструкции: {item['title']}"
                        body = f"""Уважаемый {item.get('responsible', 'коллега')}!

Для должностной инструкции "{item['title']}" не загружен файл.

Дата регистрации: {item.get('registration_date', 'не указана')}

Просьба загрузить файл инструкции в систему.

С уважением,
Система управления должностными инструкциями"""
                        
                        if send_email(item.get('email'), subject, body, yandex_email, yandex_password):
                            success_count += 1
                    
                    st.success(f"✅ Отправлено {success_count} из {len(instructions_without_files)} напоминаний")
                else:
                    st.error("❌ Заполните email и пароль")
    
    if not outdated_instructions and not instructions_without_files:
        st.success("✅ Все инструкции актуальны и имеют файлы. Напоминания не требуются.")

def show_statistics(data):
    """Отображение статистики и аналитики"""
    st.header("📈 Статистика и аналитика")
    
    if not data:
        st.info("📝 Нет данных для анализа. Добавьте инструкции.")
        return
    
    # Общая статистика
    st.subheader("📊 Общая статистика")
    col1, col2, col3, col4 = st.columns(4)
    
    total_instructions = len(data)
    outdated_count = sum(1 for item in data if is_outdated(item.get('last_update')))
    with_files = sum(1 for item in data if item.get('has_file'))
    without_files = total_instructions - with_files
    
    with col1:
        st.metric("Всего инструкций", total_instructions)
    with col2:
        st.metric("Требуют актуализации", outdated_count, 
                 delta=f"-{round((outdated_count/total_instructions)*100, 1)}%" if outdated_count > 0 else "0%",
                 delta_color="inverse")
    with col3:
        st.metric("С файлами", with_files,
                 delta=f"{round((with_files/total_instructions)*100, 1)}%")
    with col4:
        st.metric("Без файлов", without_files,
                 delta=f"-{round((without_files/total_instructions)*100, 1)}%" if without_files > 0 else "0%",
                 delta_color="inverse")
    
    # Графики
    st.subheader("📉 Визуализация данных")
    
    col1, col2 = st.columns(2)
    
    with col1:
        # Диаграмма актуальности
        st.markdown("**Статус актуализации**")
        status_data = pd.DataFrame({
            'Статус': ['Актуальные', 'Требуют актуализации'],
            'Количество': [total_instructions - outdated_count, outdated_count]
        })
        st.bar_chart(status_data.set_index('Статус'))
    
    with col2:
        # Диаграмма наличия файлов
        st.markdown("**Наличие файлов**")
        file_data = pd.DataFrame({
            'Статус': ['С файлами', 'Без файлов'],
            'Количество': [with_files, without_files]
        })
        st.bar_chart(file_data.set_index('Статус'))
    
    # Статистика по ответственным
    st.subheader("👥 Статистика по ответственным лицам")
    
    responsible_stats = {}
    for item in data:
        resp = item.get('responsible', 'Не указан')
        if resp not in responsible_stats:
            responsible_stats[resp] = {'total': 0, 'outdated': 0, 'without_file': 0}
        responsible_stats[resp]['total'] += 1
        if is_outdated(item.get('last_update')):
            responsible_stats[resp]['outdated'] += 1
        if not item.get('has_file'):
            responsible_stats[resp]['without_file'] += 1
    
    resp_table = []
    for resp, stats in responsible_stats.items():
        resp_table.append({
            'Ответственный': resp,
            'Всего инструкций': stats['total'],
            'Требуют актуализации': stats['outdated'],
            'Без файлов': stats['without_file']
        })
    
    if resp_table:
        df_resp = pd.DataFrame(resp_table)
        st.dataframe(df_resp, use_container_width=True)
    
    # Временная динамика актуализации
    st.subheader("📅 Динамика актуализации по месяцам")
    
    # Группировка по датам актуализации
    update_dates = []
    for item in data:
        if item.get('last_update'):
            try:
                date = datetime.strptime(item['last_update'], "%Y-%m-%d")
                update_dates.append(date.strftime("%Y-%m"))
            except:
                pass
    
    if update_dates:
        from collections import Counter
        date_counts = Counter(update_dates)
        date_df = pd.DataFrame({
            'Месяц': list(date_counts.keys()),
            'Актуализаций': list(date_counts.values())
        }).sort_values('Месяц')
        
        st.line_chart(date_df.set_index('Месяц'))
    else:
        st.info("Недостаточно данных для построения графика динамики")
    
    # История изменений
    st.subheader("📜 Последние изменения")
    
    all_changes = []
    for item in data:
        if item.get('history'):
            for entry in item['history']:
                all_changes.append({
                    'Время': entry['timestamp'],
                    'Инструкция': item['title'],
                    'Тип': entry['change_type'],
                    'Детали': entry['details']
                })
    
    if all_changes:
        all_changes_sorted = sorted(all_changes, key=lambda x: x['Время'], reverse=True)[:20]
        df_changes = pd.DataFrame(all_changes_sorted)
        st.dataframe(df_changes, use_container_width=True)
    else:
        st.info("Нет записей об изменениях")
    
    # Экспорт в Excel
    st.subheader("📥 Экспорт данных")
    
    if st.button("📊 Экспорт отчета в Excel"):
        try:
            # Создание Excel файла
            from io import BytesIO
            output = BytesIO()
            
            # Prepare data first
            df_resp_export = None
            all_changes_sorted_export = None
            
            if resp_table:
                df_resp_export = df_resp
            
            if all_changes:
                all_changes_sorted_export = all_changes_sorted
            
            with pd.ExcelWriter(output, engine='openpyxl', mode='w') as writer:
                # Основная таблица
                main_data = []
                for item in data:
                    main_data.append({
                        'Название': item.get('title', ''),
                        'Подразделение': item.get('department', 'Не указано'),
                        'Дата регистрации': item.get('registration_date', ''),
                        'Дата актуализации': item.get('last_update', ''),
                        'Ответственный': item.get('responsible', ''),
                        'Email': item.get('email', ''),
                        'Наличие файла': 'Да' if item.get('has_file') else 'Нет',
                        'Статус': 'Требует актуализации' if is_outdated(item.get('last_update')) else 'Актуальная'
                    })
                df_main = pd.DataFrame(main_data)
                df_main.to_excel(writer, sheet_name='Инструкции', index=False)
                
                # Статистика по ответственным
                if df_resp_export is not None:
                    df_resp_export.to_excel(writer, sheet_name='По ответственным', index=False)
                
                # История изменений
                if all_changes_sorted_export:
                    df_changes_full = pd.DataFrame(all_changes_sorted_export)
                    df_changes_full.to_excel(writer, sheet_name='История', index=False)
            
            output.seek(0)
            st.download_button(
                label="📥 Скачать Excel отчет",
                data=output.getvalue(),
                file_name=f"report_instructions_{datetime.now().strftime('%Y%m%d_%H%M%S')}.xlsx",
                mime="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
            )
            st.success("✅ Отчет готов к скачиванию!")
        except Exception as e:
            st.error(f"❌ Ошибка создания отчета: {str(e)}")

def auto_reminders(data):
    """Настройка автоматических напоминаний"""
    st.header("⚙️ Автоматические напоминания")
    
    st.info("""
    ℹ️ **Информация об автоматических напоминаниях**
    
    Для настройки автоматической отправки напоминаний по расписанию необходимо:
    
    1. **Использовать планировщик задач на сервере** (cron на Linux, Task Scheduler на Windows)
    2. **Создать скрипт** для автоматической отправки напоминаний
    3. **Настроить расписание** запуска скрипта
    
    Streamlit работает как веб-приложение и не может запускать фоновые задачи самостоятельно.
    """)
    
    st.subheader("📋 Рекомендуемая настройка")
    
    st.markdown("""
    ### Вариант 1: Использование cron (Linux)
    
    Создайте файл `send_reminders.py` с кодом отправки напоминаний и добавьте в crontab:
    
    ```bash
    # Отправка напоминаний каждый понедельник в 9:00
    0 9 * * 1 python /path/to/send_reminders.py
    ```
    
    ### Вариант 2: Планировщик задач Windows
    
    1. Откройте "Планировщик заданий"
    2. Создайте новую задачу
    3. Укажите триггер (например, еженедельно)
    4. Укажите действие: запуск Python скрипта
    
    ### Вариант 3: Системный сервис
    
    Создайте системный сервис, который будет проверять необходимость отправки напоминаний.
    """)
    
    st.subheader("🔧 Генератор скрипта для автоматической отправки")
    
    with st.form("script_generator"):
        yandex_email = st.text_input("📧 Email для отправки (Яндекс.Почта):")
        
        st.info("⚠️ Пароль приложения нужно будет добавить в скрипт вручную из соображений безопасности")
        
        frequency = st.selectbox("📅 Частота отправки:", [
            "Ежедневно",
            "Еженедельно (понедельник)",
            "Ежемесячно (1-е число)"
        ])
        
        time_hour = st.selectbox("🕐 Час отправки:", list(range(0, 24)), index=9)
        
        if st.form_submit_button("📝 Создать скрипт"):
            if not yandex_email:
                st.error("❌ Укажите email для отправки")
            else:
                script_content = f'''#!/usr/bin/env python3
"""
Автоматический скрипт для отправки напоминаний
Создан: {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}
"""

import json
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from datetime import datetime, timedelta

DATA_FILE = "data/instructions.json"
YANDEX_EMAIL = "{yandex_email}"
YANDEX_PASSWORD = "YOUR_APP_PASSWORD_HERE"  # Замените на пароль приложения

def load_data():
    with open(DATA_FILE, 'r', encoding='utf-8') as f:
        return json.load(f)

def is_outdated(last_update_date, months_threshold=12):
    if not last_update_date:
        return True
    try:
        update_date = datetime.strptime(last_update_date, "%Y-%m-%d")
        threshold_date = datetime.now() - timedelta(days=months_threshold * 30)
        return update_date < threshold_date
    except:
        return True

def send_email(to_email, subject, body):
    try:
        msg = MIMEMultipart()
        msg['From'] = YANDEX_EMAIL
        msg['To'] = to_email
        msg['Subject'] = subject
        
        msg.attach(MIMEText(body, 'plain', 'utf-8'))
        
        server = smtplib.SMTP('smtp.yandex.ru', 587)
        server.starttls()
        server.login(YANDEX_EMAIL, YANDEX_PASSWORD)
        text = msg.as_string()
        server.sendmail(YANDEX_EMAIL, to_email, text)
        server.quit()
        return True
    except Exception as e:
        print(f"Ошибка отправки email: {{str(e)}}")
        return False

def main():
    data = load_data()
    outdated_instructions = [item for item in data if is_outdated(item.get('last_update'))]
    
    success_count = 0
    for item in outdated_instructions:
        subject = f"Напоминание об актуализации должностной инструкции: {{item['title']}}"
        body = f"""Уважаемый {{item.get('responsible', 'коллега')}}!

Напоминаем, что должностная инструкция "{{item['title']}}" требует актуализации.

Дата последней актуализации: {{item.get('last_update', 'не указана')}}
Дата регистрации: {{item.get('registration_date', 'не указана')}}

Просьба обновить инструкцию в ближайшее время.

С уважением,
Система управления должностными инструкциями"""
        
        if send_email(item.get('email'), subject, body):
            success_count += 1
            print(f"Отправлено напоминание: {{item['title']}} -> {{item.get('responsible')}}")
    
    print(f"Всего отправлено: {{success_count}} из {{len(outdated_instructions)}} напоминаний")
    print(f"Время выполнения: {{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}}")

if __name__ == "__main__":
    main()
'''
                
                st.success("✅ Скрипт создан!")
                st.download_button(
                    label="📥 Скачать скрипт",
                    data=script_content,
                    file_name="send_reminders.py",
                    mime="text/x-python"
                )
                
                # Пример настройки cron
                if frequency == "Ежедневно":
                    cron_example = f"{time_hour} {time_hour} * * * python /path/to/send_reminders.py >> /var/log/reminders.log 2>&1"
                elif frequency == "Еженедельно (понедельник)":
                    cron_example = f"0 {time_hour} * * 1 python /path/to/send_reminders.py >> /var/log/reminders.log 2>&1"
                else:  # Ежемесячно
                    cron_example = f"0 {time_hour} 1 * * python /path/to/send_reminders.py >> /var/log/reminders.log 2>&1"
                
                st.markdown("### Пример настройки cron:")
                st.code(cron_example, language="bash")
    
    st.subheader("📊 Текущий статус напоминаний")
    
    if data:
        outdated_count = sum(1 for item in data if is_outdated(item.get('last_update')))
        no_file_count = sum(1 for item in data if not item.get('has_file'))
        
        col1, col2 = st.columns(2)
        with col1:
            st.metric("Требуют напоминания об актуализации", outdated_count)
        with col2:
            st.metric("Требуют напоминания о файлах", no_file_count)
    else:
        st.info("Нет инструкций для анализа")

if __name__ == "__main__":
    main()
