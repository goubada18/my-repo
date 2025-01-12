import java.util.Scanner;

public class Main {
    public static void main(String[] args) {
        Scanner scanner = new Scanner(System.in);
        StudentManager studentManager = new StudentManager();
        while (true) {
            System.out.println("欢迎使用学生管理系统，请选择操作：");
            System.out.println("1. 添加学生");
            System.out.println("2. 查询学生");
            System.out.println("3. 修改学生");
            System.out.println("4. 删除学生");
            System.out.println("5. 退出系统");
            int choice = scanner.nextInt();
            scanner.nextLine(); // 吸收换行符
            switch (choice) {
                case 1:
                    System.out.println("请输入学生姓名：");
                    String name = scanner.nextLine();
                    System.out.println("请输入学生性别（0表示男，1表示女）：");
                    int sex = scanner.nextInt();
                    scanner.nextLine(); // 吸收换行符
                    System.out.println("请输入学生班级ID：");
                    String classid = scanner.nextLine();
                    System.out.println("请输入学生数学成绩：");
                    double math = scanner.nextDouble();
                    System.out.println("请输入学生Java成绩：");
                    double java = scanner.nextDouble();
                    Student newStudent = new Student();
                    newStudent.setName(name);
                    newStudent.setSex(sex);
                    newStudent.setClassid(classid);
                    newStudent.setMath(math);
                    newStudent.setJava(java);
                    studentManager.addStudent(newStudent);
                    System.out.println("学生信息添加成功！");
                    break;
                case 2:
                    System.out.println("请输入要查询的学生学号：");
                    int studentId = scanner.nextInt();
                    Student queriedStudent = studentManager.queryStudentById(studentId);
                    if (queriedStudent!= null) {
                        System.out.println("学生学号：" + queriedStudent.getId());
                        System.out.println("学生姓名：" + queriedStudent.getName());
                        System.out.println("学生性别：" + queriedStudent.getSex());
                        System.out.println("学生班级ID：" + queriedStudent.getClassid());
                        System.out.println("数学成绩：" + queriedStudent.getMath());
                        System.out.println("Java成绩：" + queriedStudent.getJava());
                    } else {
                        System.out.println("未找到该学生信息！");
                    }
                    break;
                case 3:
                    System.out.println("请输入要修改的学生学号：");
                    int idToUpdate = scanner.nextInt();
                    Student studentToUpdate = studentManager.queryStudentById(idToUpdate);
                    if (studentToUpdate!= null) {
                        System.out.println("请输入新的学生姓名（原姓名：" + studentToUpdate.getName() + "）：");
                        String newName = scanner.nextLine();
                        scanner.nextLine(); // 吸收换行符
                        System.out.println("请输入新的学生性别（0表示男，1表示女，原性别：" + studentToUpdate.getSex() + "）：");
                        int newSex = scanner.nextInt();
                        scanner.nextLine(); // 吸收换行符
                        System.out.println("请输入新的学生班级ID（原班级ID：" + studentToUpdate.getClassid() + "）：");
                        String newClassid = scanner.nextLine();
                        System.out.println("请输入新的学生数学成绩（原成绩：" + studentToUpdate.getMath() + "）：");
                        double newMath = scanner.nextDouble();
                        System.out.println("请输入新的学生Java成绩（原成绩：" + studentToUpdate.getJava() + "）：");
                        double newJava = scanner.nextDouble();

                        studentToUpdate.setName(newName);
                        studentToUpdate.setSex(newSex);
                        studentToUpdate.setClassid(newClassid);
                        studentToUpdate.setMath(newMath);
                        studentToUpdate.setJava(newJava);

                        studentManager.updateStudent(studentToUpdate);
                        System.out.println("学生信息修改成功！");
                    } else {
                        System.out.println("未找到该学生信息，无法修改！");
                    }
                    break;
                case 4:
                    System.out.println("请输入要删除的学生学号：");
                    int idToDelete = scanner.nextInt();
                    boolean isDeleted = studentManager.deleteStudent(idToDelete);
                    if (isDeleted) {
                        System.out.println("学生信息删除成功！");
                    } else {
                        System.out.println("未找到该学生信息，删除失败！");
                    }
                    break;
                case 5:
                    System.out.println("感谢使用，再见！");
                    scanner.close();
                    System.exit(0);
                default:
                    System.out.println("无效的选择，请重新输入！");
            }
        }
    }
}